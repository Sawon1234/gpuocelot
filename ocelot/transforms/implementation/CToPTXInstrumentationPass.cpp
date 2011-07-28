/*! \file CToPTXInstrumentationPass.cpp
	\date Tuesday July 1, 2011
	\author Naila Farooqui <naila@cc.gatech.edu>
	\brief The source file for the CToPTXInstrumentationPass class
*/

#ifndef C_TO_PTX_INSTRUMENTATION_PASS_CPP_INCLUDED
#define C_TO_PTX_INSTRUMENTATION_PASS_CPP_INCLUDED

#include <ocelot/transforms/interface/CToPTXInstrumentationPass.h>
#include <ocelot/ir/interface/Module.h>
#include <ocelot/ir/interface/PTXStatement.h>
#include <ocelot/ir/interface/PTXInstruction.h>
#include <ocelot/ir/interface/PTXOperand.h>
#include <ocelot/ir/interface/PTXKernel.h>
#include <ocelot/analysis/interface/DataflowGraph.h>

namespace transforms
{

    analysis::DataflowGraph& CToPTXInstrumentationPass::dfg()
	{
		analysis::Analysis* graph = getAnalysis(
			analysis::Analysis::DataflowGraphAnalysis);

		assert(graph != 0);
		
		return static_cast<analysis::DataflowGraph&>(*graph);
	}

    /* This method assigns unused registers for each PTX statement to be inserted and replaces all static attribute place-holders with actual values */
    ir::PTXStatement CToPTXInstrumentationPass::prepareStatementToInsert(ir::PTXStatement statement, StaticAttributes attributes) {
    
        ir::PTXStatement toInsert = statement;
        
        if(statement.instruction.a.identifier == BASIC_BLOCK_EXEC_INST_COUNT && statement.instruction.d.identifier == BASIC_BLOCK_EXEC_INST_COUNT)
        {
            toInsert.instruction.d.reg = toInsert.instruction.a.reg = newRegisterMap[BASIC_BLOCK_EXEC_INST_COUNT];
            toInsert.instruction.d.identifier.clear();
            toInsert.instruction.a.identifier.clear();
            
            return toInsert;
        }
        
        if(statement.instruction.d.identifier == BASIC_BLOCK_INST_COUNT || 
            statement.instruction.d.identifier == BASIC_BLOCK_EXEC_INST_COUNT ||
            statement.instruction.d.identifier == BASIC_BLOCK_ID || 
            statement.instruction.d.identifier == INSTRUCTION_ID) {
            toInsert.instruction.d.reg = dfg().newRegister();
            newRegisterMap[toInsert.instruction.d.identifier] = toInsert.instruction.d.reg;
            toInsert.instruction.d.identifier.clear();
            
            if(statement.instruction.d.identifier == BASIC_BLOCK_INST_COUNT) 
                toInsert.instruction.a.imm_int = attributes.basicBlockInstructionCount;
            else if(statement.instruction.d.identifier == BASIC_BLOCK_EXEC_INST_COUNT) 
                toInsert.instruction.a.imm_int = attributes.basicBlockExecutedInstructionCount;
            else if(statement.instruction.d.identifier == BASIC_BLOCK_ID)    
                toInsert.instruction.a.imm_int = attributes.basicBlockId; 
            else if(statement.instruction.d.identifier == INSTRUCTION_ID)    
                toInsert.instruction.a.imm_int = attributes.instructionId;
                 
            return toInsert;
        }
        
        ir::PTXOperand ir::PTXInstruction::* operands[] = { &ir::PTXInstruction::a, & ir::PTXInstruction::b, & ir::PTXInstruction::c, 
            & ir::PTXInstruction::d, & ir::PTXInstruction::pg };

        for (int i = 0; i < 5; i++) {
            ir::PTXOperand &operand = statement.instruction.*(operands[i]);
           
            if((operand.addressMode == ir::PTXOperand::Register ||
                operand.addressMode == ir::PTXOperand::Indirect ||
                (operand.condition == ir::PTXOperand::Pred && operand.addressMode != ir::PTXOperand::Address)) &&
                 !operand.identifier.empty()) {
                (toInsert.instruction.*(operands[i])).reg = newRegisterMap[operand.identifier];
                (toInsert.instruction.*(operands[i])).identifier.clear();
            }
        }
        
        if(statement.instruction.opcode == ir::PTXInstruction::Vote){
            toInsert.instruction.a = attributes.predicateGuard;
        }

        return toInsert;
    }

    bool CToPTXInstrumentationPass::instrumentationConditionsMet(ir::PTXInstruction instruction, TranslationBlock translationBlock)
    {
        bool instructionClassValid = false;
        bool addressSpaceValid = false;
        bool dataTypeValid = false;
                
        if(translationBlock.specifier.instructionClassVector.empty())
        {
            instructionClassValid = true;
        }
        else
        {  
            instructionClassValid = false;

            for (InstrumentationSpecifier::StringVector::iterator instClass = translationBlock.specifier.instructionClassVector.begin(); 
                instClass != translationBlock.specifier.instructionClassVector.end(); ++instClass) 
            {
                if(*instClass == ON_PREDICATED)
                {
                    translationBlock.specifier.isPredicated = true;
                    
                    if(instruction.pg.condition == ir::PTXOperand::Pred || instruction.pg.condition == ir::PTXOperand::InvPred) 
                    {
                       instructionClassValid = true;
                       break;
                    }        
                }
                else if(opcodeMap[instruction.opcode] == *instClass)
                {
                    if(*instClass == ON_BRANCH && translationBlock.specifier.isPredicated)
                        break;
                        
                    instructionClassValid = true;
                    break;
                }       
            }    
        }          
        
        if(translationBlock.specifier.addressSpaceVector.empty())
        {
            addressSpaceValid = true;
        }
        else 
        {
            addressSpaceValid = false;
            for(InstrumentationSpecifier::StringVector::iterator addressSpace = translationBlock.specifier.addressSpaceVector.begin();
                            addressSpace != translationBlock.specifier.addressSpaceVector.end(); ++addressSpace)
            {
                if(addressSpaceMap[*addressSpace] == instruction.addressSpace)
                {
                    addressSpaceValid = true;
                    break;
                }        
            }
        
        }
        
        if(translationBlock.specifier.dataTypeVector.empty())
        {
            dataTypeValid = true;
        }
        else 
        {
            dataTypeValid = false;
            for(InstrumentationSpecifier::StringVector::iterator dataType = translationBlock.specifier.dataTypeVector.begin();
                            dataType != translationBlock.specifier.dataTypeVector.end(); ++dataType)
            {
                if(dataTypeMap[instruction.type] == *dataType)
                {
                    dataTypeValid = true;
                }        
            }
        
        }
        return (instructionClassValid && addressSpaceValid && dataTypeValid);
    }

    void CToPTXInstrumentationPass::insertBefore(TranslationBlock translationBlock, StaticAttributes attributes, analysis::DataflowGraph::iterator basicBlock, unsigned int loc)
    {
        for( unsigned int j = 0; j < translationBlock.statements.size(); j++) {
            ir::PTXStatement toInsert = prepareStatementToInsert(translationBlock.statements.at(j), attributes);
            if(toInsert.instruction.opcode == ir::PTXInstruction::Nop)
                continue;
            dfg().insert(basicBlock, toInsert.instruction, loc++);
        }
    }
    
    void CToPTXInstrumentationPass::insertAfter(TranslationBlock translationBlock, StaticAttributes attributes, analysis::DataflowGraph::iterator basicBlock, unsigned int loc)
    {
        for( unsigned int j = 0; j < translationBlock.statements.size(); j++) {
            ir::PTXStatement toInsert = prepareStatementToInsert(translationBlock.statements.at(j), attributes);
            if(toInsert.instruction.opcode == ir::PTXInstruction::Nop)
                continue;
            dfg().insert(basicBlock, toInsert.instruction, ++loc);
        }
    }

    void CToPTXInstrumentationPass::instrumentInstruction(TranslationBlock translationBlock) 
    {
        StaticAttributes attributes;
        attributes.basicBlockId = 0;
        
        analysis::DataflowGraph::iterator block = dfg().begin();
        ++block;
        
        /* Iterating through each basic block */
        for( analysis::DataflowGraph::iterator basicBlock = block; 
            basicBlock != dfg().end(); ++basicBlock )
        {
           if(basicBlock->instructions().empty())
              continue;
            
            /* Update basicBlockInstructionCount to include all instructions in the basic block by default */
            attributes.basicBlockInstructionCount = basicBlock->instructions().size();
            unsigned int loc = 0;
                        
            attributes.instructionId = 0;
            /* Iterating through each instruction */
            for( analysis::DataflowGraph::InstructionVector::const_iterator instruction = basicBlock->instructions().begin();
                instruction != basicBlock->instructions().end(); ++instruction)
            {
            
                ir::PTXInstruction *ptxInstruction = (ir::PTXInstruction *)instruction->i;
                /* Save the predicate guard for this instruction */
                if(ptxInstruction->pg.condition == ir::PTXOperand::Pred || ptxInstruction->pg.condition == ir::PTXOperand::InvPred){
                    attributes.predicateGuard = ptxInstruction->pg;
                }    
                
                if(instrumentationConditionsMet(*ptxInstruction, translationBlock))
                {
                    insertBefore(translationBlock, attributes, basicBlock, loc);
                    loc += translationBlock.statements.size();
                    attributes.instructionId++;
                }
                loc++;
            }
            
           attributes.basicBlockId++;          
        }    
    }


    void CToPTXInstrumentationPass::instrumentBasicBlock(TranslationBlock translationBlock) 
    {
        StaticAttributes attributes;
        attributes.basicBlockId = 0;
        attributes.basicBlockInstructionCount = 0;
        
        analysis::DataflowGraph::iterator block = dfg().begin();
        ++block;
        
        /* Iterating through each basic block */
        for( analysis::DataflowGraph::iterator basicBlock = block; 
            basicBlock != dfg().end(); ++basicBlock )
        {        
           if(basicBlock->instructions().empty())
              continue;
                
            attributes.basicBlockInstructionCount = 0;
            attributes.basicBlockExecutedInstructionCount = 0;
            
            /* Iterating through each instruction */
            for( analysis::DataflowGraph::InstructionVector::const_iterator instruction = basicBlock->instructions().begin();
                instruction != basicBlock->instructions().end(); ++instruction)
            {
                ir::PTXInstruction *ptxInstruction = (ir::PTXInstruction *)instruction->i;
                if(instrumentationConditionsMet(*ptxInstruction, translationBlock)) 
                {
                    attributes.basicBlockInstructionCount++;
                    
                    if(translationBlock.specifier.checkForPredication && 
                        (ptxInstruction->pg.condition == ir::PTXOperand::Pred || ptxInstruction->pg.condition == ir::PTXOperand::InvPred)){
                        
                         InstrumentationSpecifier::StringVector::iterator found = std::find(translationBlock.specifier.predicateVector.begin(), 
                            translationBlock.specifier.predicateVector.end(), ptxInstruction->pg.toString());
                            
                        if(found == translationBlock.specifier.predicateVector.end())
                        { 
                            translationBlock.specifier.predicateVector.push_back(ptxInstruction->pg.toString());
                           
                            analysis::DataflowGraph::RegisterId predCount = dfg().newRegister();
                    
                            ir::PTXOperand::DataType type = (sizeof(size_t) == 8 ? ir::PTXOperand::u64: ir::PTXOperand::u32);
                            ir::PTXInstruction selp(ir::PTXInstruction::SelP);
	                        selp.type = selp.d.type = selp.b.type = selp.a.type = selp.c.type = type;
	                        selp.d.addressMode = selp.c.addressMode = ir::PTXOperand::Register;
	                        selp.a.addressMode = selp.b.addressMode = ir::PTXOperand::Immediate;
	                        
	                        selp.d.reg = predCount;
	                        selp.b.imm_int = 0;
	                        selp.a.imm_int = 1;
	                        selp.c = ptxInstruction->pg;

	                        
	                        ir::PTXInstruction add(ir::PTXInstruction::Add);
                            add.type = add.d.type = add.a.type = add.b.type = type;
                            add.d.addressMode = add.a.addressMode = add.b.addressMode = ir::PTXOperand::Register;
                            
                            add.d.identifier = add.a.identifier = BASIC_BLOCK_EXEC_INST_COUNT;
                            add.b.reg = predCount;
                            
                            ir::PTXStatement stmt(ir::PTXStatement::Instr);
                            stmt.instruction = selp;
                            translationBlock.statements.insert(translationBlock.statements.end() - 7, stmt);
                            stmt.instruction = add;
                            translationBlock.statements.insert(translationBlock.statements.end() - 7, stmt);
                        }
                        
                    }
                    else
                    {
                        attributes.basicBlockExecutedInstructionCount++;
                    }
                }        
            }
            
            
            unsigned int loc = 0;
            
            /* if we are inserting at the end of the basic block, make sure to insert just before the last statement, which is most likely a
                control-flow statement */
            if(translationBlock.label == EXIT_BASIC_BLOCK)
                loc = basicBlock->instructions().size() - 1;
            
            insertBefore(translationBlock, attributes, basicBlock, loc);
            
            if(translationBlock.specifier.checkForPredication)
            {
                for(ir::PTXKernel::PTXStatementVector::iterator statement = translationBlock.statements.begin();
                statement != translationBlock.statements.end(); ++statement) {
                
                    if(statement->instruction.opcode == ir::PTXInstruction::SelP && (statement+1)->instruction.opcode == ir::PTXInstruction::Add)
                    {
                        translationBlock.statements.erase(statement, statement + 2);
                    } 
                
                }
            }
            
            attributes.basicBlockId++;          
        }    
    }

    void CToPTXInstrumentationPass::instrumentKernel(TranslationBlock translationBlock) 
    {
        StaticAttributes attributes;
        attributes.basicBlockId = 0;
        attributes.instructionId = 0;
        attributes.kernelInstructionCount = 0;
                
        /* ensure that there is at least one basic block -- otherwise, skip this kernel */
        if(dfg().empty())
            return;
        
        /* by default, insert each statement to the beginning of the kernel */
	    analysis::DataflowGraph::iterator block = dfg().begin();
	    ++block;
	    
	    attributes.kernelInstructionCount = 0;
	    
	    for( analysis::DataflowGraph::iterator basicBlock = block; 
            basicBlock != dfg().end(); ++basicBlock )
        {
            if(basicBlock->instructions().empty())
              continue;
            
            /* Iterating through each instruction */
            for( analysis::DataflowGraph::InstructionVector::const_iterator instruction = basicBlock->instructions().begin();
                instruction != basicBlock->instructions().end(); ++instruction)
            {
                ir::PTXInstruction *ptxInstruction = (ir::PTXInstruction *)instruction->i;
                if(instrumentationConditionsMet(*ptxInstruction, translationBlock))
                    attributes.kernelInstructionCount++;
            }
        }
	    
	    unsigned int loc = 0;
        
        /* if inserting at the end of the kernel, insert right before the last statement in the kernel, which is most likely
            an exit or return instruction */
        if(translationBlock.label == EXIT_KERNEL) {    
            block = --(dfg().end());
            while(block->instructions().size() == 0) {
                block--;
            }
            loc = block->instructions().size() - 1;
        }
        
        insertBefore(translationBlock, attributes, block, loc);
    }

    void CToPTXInstrumentationPass::runOnKernel( ir::IRKernel & k)
	{
	    std::vector<TranslationBlock> translationBlocks;

	    for(translator::CToPTXData::RegisterVector::const_iterator reg = translation.registers.begin();
	        reg != translation.registers.end(); ++reg) {
	        newRegisterMap[*reg] = dfg().newRegister();   
	    }
        
        TranslationBlock initialBlock;
        
        for(ir::PTXKernel::PTXStatementVector::const_iterator statement = translation.statements.begin();
            statement != translation.statements.end(); ++statement) {
            
            /* check if predication is enabled */
            if(statement->directive == ir::PTXStatement::Instr && statement->instruction.d.identifier == BASIC_BLOCK_EXEC_INST_COUNT)
            {
                if(translationBlocks.size() > 0){
                    transforms::TranslationBlock last = translationBlocks.back();
                    last.specifier.checkForPredication = true;
                    translationBlocks.pop_back();
                    translationBlocks.push_back(last);
                }
                else {
                    initialBlock.specifier.checkForPredication = true;
                }
            }
                
            
            /* check if a label was encountered */
            if(statement->directive == ir::PTXStatement::Label) {
                
                /* if the label specifies the instruction class, update the instrumentation specifier in the 
                    most recently inserted translation block with this information */        
                for(std::vector<std::string>::const_iterator instClass = instructionClasses.begin(); instClass != instructionClasses.end();
                    instClass++)
                {
                    if(statement->name == *instClass){
                        
                        if(translationBlocks.size() > 0){
                            transforms::TranslationBlock last = translationBlocks.back();
                            last.specifier.instructionClassVector.push_back(*instClass);
                            translationBlocks.pop_back();
                            translationBlocks.push_back(last);
                        }
                        else {
                            initialBlock.specifier.instructionClassVector.push_back(*instClass);
                        }
                        break;
                    }
                }
                
                /* if the label specifies the address space, update the instrumentation specifier in the 
                    most recently inserted translation block with this information */     
                for(std::vector<std::string>::const_iterator addressSpace = addressSpaceSpecifiers.begin(); addressSpace != addressSpaceSpecifiers.end();
                    addressSpace++)
                {
                    if(statement->name == *addressSpace){
                        
                        if(translationBlocks.size() > 0){
                            transforms::TranslationBlock last = translationBlocks.back();
                            last.specifier.addressSpaceVector.push_back(*addressSpace);
                            translationBlocks.pop_back();
                            translationBlocks.push_back(last);
                        }
                        else {
                            initialBlock.specifier.addressSpaceVector.push_back(*addressSpace);
                        }
                        break;
                    }
                }
                
                /* if the label specifies the type, update the instrumentation specifier in the 
                    most recently inserted translation block with this information */     
                for(std::vector<std::string>::const_iterator type = types.begin(); type != types.end();
                    type++)
                {
                    if(statement->name == *type){

                        if(translationBlocks.size() > 0){
                            transforms::TranslationBlock last = translationBlocks.back();
                            last.specifier.dataTypeVector.push_back(*type);
                            translationBlocks.pop_back();
                            translationBlocks.push_back(last);
                        }
                        else {
                            initialBlock.specifier.dataTypeVector.push_back(*type);
                        }
                        break;
                    }
                
                }
                /* if an instrumentation target specifier is found, start a new translation block */
                if(statement->name == ENTER_KERNEL || statement->name == EXIT_KERNEL || statement->name == ENTER_BASIC_BLOCK || statement->name == EXIT_BASIC_BLOCK ||
                    statement->name == ON_INSTRUCTION) {
                    
                    TranslationBlock translationBlock;
                    translationBlock.label = translationBlock.specifier.id = statement->name;
                    translationBlock.target = TranslationBlock::KERNEL;
                    
                    if(statement->name == ON_INSTRUCTION)
                    {
                        translationBlock.target = TranslationBlock::INSTRUCTION;
                    }
                    else if(statement->name == ENTER_BASIC_BLOCK || statement->name == EXIT_BASIC_BLOCK)
                    {
                        translationBlock.target = TranslationBlock::BASIC_BLOCK;
                    }
                    
                    translationBlocks.push_back(translationBlock);
                    
                }
                
                continue;
            }
            
            /* insert each statement that is NOT a label into the most recently inserted translation block */
            if(translationBlocks.size() > 0){
                transforms::TranslationBlock last = translationBlocks.back();
                last.statements.push_back(*statement);
                translationBlocks.pop_back();
                translationBlocks.push_back(last);
            }
            /* if no translation blocks have been added, insert the statement into the initial block */
            else {
                initialBlock.statements.push_back(*statement);
            }
        }
        
        unsigned int j = 0;
        for(j = 0; j < translationBlocks.size(); j++)
        {
            switch(translationBlocks.at(j).target){
                case TranslationBlock::INSTRUCTION:
                    instrumentInstruction(translationBlocks.at(j));
                break;
                case TranslationBlock::BASIC_BLOCK:
                    instrumentBasicBlock(translationBlocks.at(j));
                break;
                case TranslationBlock::KERNEL:
                    instrumentKernel(translationBlocks.at(j));
                break;
                default:
                    instrumentKernel(translationBlocks.at(j));
                break;
            }
        }
        
            
        /* insert initial translation block at the beginning of the kernel -- this is the default case */
        instrumentKernel(initialBlock);
	}
	
    void CToPTXInstrumentationPass::initialize( ir::Module& m )
	{   
	    /* inserting globals into the module */
	    for(ir::PTXKernel::PTXStatementVector::const_iterator global = translation.globals.begin();
	        global != translation.globals.end(); ++global) {
            m.insertGlobalAsStatement(*global);
	    }
	}

    void CToPTXInstrumentationPass::finalize( )
	{
	
	}
	
    CToPTXInstrumentationPass::CToPTXInstrumentationPass(std::string resource)
		: KernelPass( Analysis::DataflowGraphAnalysis,
			"CToPTXInstrumentationPass" )
	{
	    translator::CToPTXTranslator translator;
	    translation = translator.generate(resource);
	    baseAddress = translation.globals.front().name;
	
	    instructionClasses = { ON_MEM_READ, ON_MEM_WRITE, ON_PREDICATED, ON_BRANCH, ON_CALL, ON_BARRIER, ON_ATOMIC, ON_ARITH_OP };
	    addressSpaceSpecifiers = { GLOBAL, LOCAL, SHARED, CONST, PARAM, TEXTURE };
	    types = { TYPE_INT, TYPE_FP };
	    
	    opcodeMap[ir::PTXInstruction::Ld] = ON_MEM_READ;
	    opcodeMap[ir::PTXInstruction::St] = ON_MEM_WRITE;
	    opcodeMap[ir::PTXInstruction::Bra] = ON_BRANCH;
	    opcodeMap[ir::PTXInstruction::Call] = ON_CALL;
	    opcodeMap[ir::PTXInstruction::Bar] = ON_BARRIER;
	    opcodeMap[ir::PTXInstruction::Membar] = ON_BARRIER;
	    opcodeMap[ir::PTXInstruction::Atom] = ON_ATOMIC;
	    opcodeMap[ir::PTXInstruction::Abs] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::Add] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::AddC] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::Bfe] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::Bfi] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::Bfind] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::Brev] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::Clz] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::Cos] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::Div] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::Mad24] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::Max] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::Min] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::Mul24] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::Mul] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::Popc] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::Prmt] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::Sad] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::Abs] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::Sqrt] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::Sin] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::Sub] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::SubC] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::TestP] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::CopySign] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::Lg2] = ON_ARITH_OP;
	    opcodeMap[ir::PTXInstruction::Ex2] = ON_ARITH_OP;
        opcodeMap[ir::PTXInstruction::Neg] = ON_ARITH_OP;
	   
	    addressSpaceMap[GLOBAL] = ir::PTXInstruction::Global;
	    addressSpaceMap[LOCAL] = ir::PTXInstruction::Local;
	    addressSpaceMap[SHARED] = ir::PTXInstruction::Shared;
	    addressSpaceMap[CONST] = ir::PTXInstruction::Const;
	    addressSpaceMap[PARAM] = ir::PTXInstruction::Param;
	    addressSpaceMap[TEXTURE] = ir::PTXInstruction::Texture;
	   
	    dataTypeMap[ir::PTXOperand::s8] = TYPE_INT;
	    dataTypeMap[ir::PTXOperand::s16] = TYPE_INT;
	    dataTypeMap[ir::PTXOperand::s32] = TYPE_INT;
	    dataTypeMap[ir::PTXOperand::s64] = TYPE_INT;
	    dataTypeMap[ir::PTXOperand::u8] = TYPE_INT;
	    dataTypeMap[ir::PTXOperand::u16] = TYPE_INT;
	    dataTypeMap[ir::PTXOperand::u32] = TYPE_INT;
	    dataTypeMap[ir::PTXOperand::u64] = TYPE_INT;
	    dataTypeMap[ir::PTXOperand::f16] = TYPE_FP;
	    dataTypeMap[ir::PTXOperand::f32] = TYPE_FP;
	    dataTypeMap[ir::PTXOperand::f64] = TYPE_FP;
	}
	
	InstrumentationSpecifier::InstrumentationSpecifier()
	    : checkForPredication(false), isPredicated(false)
	    {
	    }
}


#endif
