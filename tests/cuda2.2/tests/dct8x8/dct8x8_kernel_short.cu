/*
* Copyright 1993-2007 NVIDIA Corporation.  All rights reserved.
*
* NOTICE TO USER:
*
* This source code is subject to NVIDIA ownership rights under U.S. and
* international Copyright laws.  Users and possessors of this source code
* are hereby granted a nonexclusive, royalty-free license to use this code
* in individual and commercial software.
*
* NVIDIA MAKES NO REPRESENTATION ABOUT THE SUITABILITY OF THIS SOURCE
* CODE FOR ANY PURPOSE.  IT IS PROVIDED "AS IS" WITHOUT EXPRESS OR
* IMPLIED WARRANTY OF ANY KIND.  NVIDIA DISCLAIMS ALL WARRANTIES WITH
* REGARD TO THIS SOURCE CODE, INCLUDING ALL IMPLIED WARRANTIES OF
* MERCHANTABILITY, NONINFRINGEMENT, AND FITNESS FOR A PARTICULAR PURPOSE.
* IN NO EVENT SHALL NVIDIA BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL,
* OR CONSEQUENTIAL DAMAGES, OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS
* OF USE, DATA OR PROFITS,  WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE
* OR OTHER TORTIOUS ACTION,  ARISING OUT OF OR IN CONNECTION WITH THE USE
* OR PERFORMANCE OF THIS SOURCE CODE.
*
* U.S. Government End Users.   This source code is a "commercial item" as
* that term is defined at  48 C.F.R. 2.101 (OCT 1995), consisting  of
* "commercial computer  software"  and "commercial computer software
* documentation" as such terms are  used in 48 C.F.R. 12.212 (SEPT 1995)
* and is provided to the U.S. Government only as a commercial end item.
* Consistent with 48 C.F.R.12.212 and 48 C.F.R. 227.7202-1 through
* 227.7202-4 (JUNE 1995), all U.S. Government End Users acquire the
* source code with only those rights set forth herein.
*
* Any use of this source code in individual and commercial software must
* include, in the user documentation and internal comments to the code,
* the above Disclaimer and U.S. Government End Users Notice.
*/

/**
**************************************************************************
* \file dct8x8_kernel_short.cu
* \brief Contains kernel implementations of DCT and IDCT routines for 16-bit
*        integers, used in JPEG internal data processing. Optimized device code.
*
* This code implements traditional approach to forward and inverse Discrete 
* Cosine Transform to blocks of image pixels (of 8x8 size), as in JPEG standard. 
* The data processing is performed using short data type.
* The routine that performs quantization of coefficients can be found in 
* dct8x8_kernel_quantization.cu file.
*/

#pragma once

#include "Common.h"


/**
*  Width of data block (short kernel)
*/
#define KERS_BLOCK_WIDTH			32


/**
*  Height of data block (short kernel)
*/
#define KERS_BLOCK_HEIGHT			32


/**
*  LOG2 of width of data block (short kernel)
*/
#define KERS_BW_LOG2				5


/**
*  LOG2 of height of data block (short kernel)
*/
#define KERS_BH_LOG2				5


/**
*  Stride of shared memory buffer (short kernel)
*/
#define KERS_SMEMBLOCK_STRIDE		(KERS_BLOCK_WIDTH + 2)


/**
*  Half of data block width (short kernel)
*/
#define KERS_BLOCK_WIDTH_HALF		(KERS_BLOCK_WIDTH / 2)


#define SIN_1_4		0x5A82
#define COS_1_4		0x5A82
#define SIN_1_8		0x30FC
#define COS_1_8		0x7642

#define OSIN_1_16	0x063E
#define OSIN_3_16	0x11C7
#define OSIN_5_16	0x1A9B
#define OSIN_7_16	0x1F63

#define OCOS_1_16	0x1F63
#define OCOS_3_16	0x1A9B
#define OCOS_5_16	0x11C7
#define OCOS_7_16	0x063E


/**
*  Package of 2 shorts into 1 int - designed to perform i/o by integers to avoid bank conflicts
*/
union PackedShorts
{
	struct __align__(8) 
	{
		short hShort1;
		short hShort2;
	};
	unsigned int hInt;
};


/**
*  Converts fixed point value to short value
*/
__device__ inline short unfixh(int x)
{
	return (short)((x + 0x8000) >> 16);
}


/**
*  Converts fixed point value to short value
*/
__device__ inline int unfixo(int x)
{
	return (x + 0x1000) >> 13;
}


/**
**************************************************************************
*  Performs in-place DCT of vector of 8 elements (used to access columns in shared memory).
*
* \param SrcDst			[IN/OUT] - Pointer to the first element of vector
* \param Stride			[IN] - Value to add to ptr to access other elements 
*  
* \return None
*/
__device__ void CUDAshortInplaceDCT(short *SrcDst, int Stride)
{
	int in0, in1, in2, in3, in4, in5, in6, in7;
	int tmp0, tmp1, tmp2, tmp3, tmp4, tmp5, tmp6, tmp7;
	int tmp10, tmp11, tmp12, tmp13;
	int tmp14, tmp15, tmp16, tmp17;
	int tmp25, tmp26;

	int DoubleStride = Stride << 1;

	short *DstPtr = SrcDst;
	in0 = *DstPtr; 
	DstPtr += Stride;
	in1 = *DstPtr; 
	DstPtr += Stride;
	in2 = *DstPtr; 
	DstPtr += Stride;
	in3 = *DstPtr; 
	DstPtr += Stride;
	in4 = *DstPtr; 
	DstPtr += Stride;
	in5 = *DstPtr; 
	DstPtr += Stride;
	in6 = *DstPtr; 
	DstPtr += Stride;
	in7 = *DstPtr; 

	tmp0 = in7 + in0;
	tmp1 = in6 + in1;
	tmp2 = in5 + in2;
	tmp3 = in4 + in3;
	tmp4 = in3 - in4;
	tmp5 = in2 - in5;
	tmp6 = in1 - in6;
	tmp7 = in0 - in7;

	tmp10 = tmp3 + tmp0;
	tmp11 = tmp2 + tmp1;
	tmp12 = tmp1 - tmp2;
	tmp13 = tmp0 - tmp3;

	tmp16 = unfixo(FMUL(tmp6 + tmp5, SIN_1_4));
	tmp15 = unfixo(FMUL(tmp6 - tmp5, COS_1_4));

	tmp4 <<= 2;
	tmp7 <<= 2;

	tmp14 = tmp4 + tmp15;
	tmp25 = tmp4 - tmp15;
	tmp26 = tmp7 - tmp16;
	tmp17 = tmp7 + tmp16;

	DstPtr = SrcDst;
	*DstPtr = unfixh(FMUL(tmp10 + tmp11, SIN_1_4));
	DstPtr += DoubleStride;
	*DstPtr = unfixh(FMUL(tmp13, COS_1_8) + FMUL(tmp12, SIN_1_8));
	DstPtr += DoubleStride;
	*DstPtr = unfixh(FMUL(tmp10 - tmp11, COS_1_4));
	DstPtr += DoubleStride;
	*DstPtr = unfixh(FMUL(tmp13, SIN_1_8) - FMUL(tmp12, COS_1_8));

	DstPtr = SrcDst + Stride;
	*DstPtr = unfixh(FMUL(tmp17, OCOS_1_16) + FMUL(tmp14, OSIN_1_16));
	DstPtr += DoubleStride;
	*DstPtr = unfixh(FMUL(tmp26, OCOS_3_16) - FMUL(tmp25, OSIN_3_16));
	DstPtr += DoubleStride;
	*DstPtr = unfixh(FMUL(tmp26, OCOS_5_16) + FMUL(tmp25, OSIN_5_16));
	DstPtr += DoubleStride;
	*DstPtr = unfixh(FMUL(tmp17, OCOS_7_16) - FMUL(tmp14, OSIN_7_16));
}


/**
**************************************************************************
*  Performs in-place DCT of vector of 8 elements (used to access rows in shared memory).
*
* \param V8			[IN/OUT] - Pointer to the first two elements of vector
*  
* \return None
*/
__device__ void CUDAshortInplaceDCT(unsigned int *V8)
{
	int in0, in1, in2, in3, in4, in5, in6, in7;
	int tmp0, tmp1, tmp2, tmp3, tmp4, tmp5, tmp6, tmp7;
	int tmp10, tmp11, tmp12, tmp13;
	int tmp14, tmp15, tmp16, tmp17;
	int tmp25, tmp26;
	PackedShorts sh0, sh1, sh2, sh3;

	sh0.hInt = V8[0];
	sh1.hInt = V8[1];
	sh2.hInt = V8[2];
	sh3.hInt = V8[3];
	in0 = sh0.hShort1;
	in1 = sh0.hShort2;
	in2 = sh1.hShort1;
	in3 = sh1.hShort2;
	in4 = sh2.hShort1;
	in5 = sh2.hShort2;
	in6 = sh3.hShort1;
	in7 = sh3.hShort2;

	tmp0 = in7 + in0;
	tmp1 = in6 + in1;
	tmp2 = in5 + in2;
	tmp3 = in4 + in3;
	tmp4 = in3 - in4;
	tmp5 = in2 - in5;
	tmp6 = in1 - in6;
	tmp7 = in0 - in7;

	tmp10 = tmp3 + tmp0;
	tmp11 = tmp2 + tmp1;
	tmp12 = tmp1 - tmp2;
	tmp13 = tmp0 - tmp3;

	sh0.hShort1 = unfixh(FMUL(tmp10 + tmp11, SIN_1_4));
	sh2.hShort1 = unfixh(FMUL(tmp10 - tmp11, COS_1_4));

	sh1.hShort1 = unfixh(FMUL(tmp13, COS_1_8) + FMUL(tmp12, SIN_1_8));
	sh3.hShort1 = unfixh(FMUL(tmp13, SIN_1_8) - FMUL(tmp12, COS_1_8));

	tmp16 = unfixo(FMUL(tmp6 + tmp5, SIN_1_4));
	tmp15 = unfixo(FMUL(tmp6 - tmp5, COS_1_4));

	tmp4 <<= 2;
	tmp7 <<= 2;

	tmp14 = tmp4 + tmp15;
	tmp25 = tmp4 - tmp15;
	tmp26 = tmp7 - tmp16;
	tmp17 = tmp7 + tmp16;

	sh0.hShort2 = unfixh(FMUL(tmp17, OCOS_1_16) + FMUL(tmp14, OSIN_1_16));
	sh3.hShort2 = unfixh(FMUL(tmp17, OCOS_7_16) - FMUL(tmp14, OSIN_7_16));
	sh2.hShort2 = unfixh(FMUL(tmp26, OCOS_5_16) + FMUL(tmp25, OSIN_5_16));
	sh1.hShort2 = unfixh(FMUL(tmp26, OCOS_3_16) - FMUL(tmp25, OSIN_3_16));

	V8[0] = sh0.hInt;
	V8[1] = sh1.hInt;
	V8[2] = sh2.hInt;
	V8[3] = sh3.hInt;
}


/**
**************************************************************************
*  Performs in-place IDCT of vector of 8 elements (used to access columns in shared memory).
*
* \param SrcDst			[IN/OUT] - Pointer to the first element of vector
* \param Stride			[IN] - Value to add to ptr to access other elements 
*  
* \return None
*/
__device__ void CUDAshortInplaceIDCT(short *SrcDst, int Stride)
{
	int in0, in1, in2, in3, in4, in5, in6, in7;
	int tmp10, tmp11, tmp12, tmp13;
	int tmp20, tmp21, tmp22, tmp23;
	int tmp30, tmp31;
	int tmp40, tmp41, tmp42, tmp43;
	int tmp50, tmp51, tmp52, tmp53;

	short *DstPtr = SrcDst;
	in0 = *DstPtr; 
	DstPtr += Stride;
	in1 = *DstPtr; 
	DstPtr += Stride;
	in2 = *DstPtr; 
	DstPtr += Stride;
	in3 = *DstPtr; 
	DstPtr += Stride;
	in4 = *DstPtr; 
	DstPtr += Stride;
	in5 = *DstPtr; 
	DstPtr += Stride;
	in6 = *DstPtr; 
	DstPtr += Stride;
	in7 = *DstPtr; 

	tmp10 = FMUL(in0 + in4, COS_1_4);
	tmp11 = FMUL(in0 - in4, COS_1_4);
	tmp12 = FMUL(in2, SIN_1_8) - FMUL(in6, COS_1_8);
	tmp13 = FMUL(in6, SIN_1_8) + FMUL(in2, COS_1_8);

	tmp20 = tmp10 + tmp13;
	tmp21 = tmp11 + tmp12;
	tmp22 = tmp11 - tmp12;
	tmp23 = tmp10 - tmp13;

	tmp30 = unfixo(FMUL(in3 + in5, COS_1_4));
	tmp31 = unfixo(FMUL(in3 - in5, COS_1_4));

	in1 <<= 2;
	in7 <<= 2;

	tmp40 = in1 + tmp30;
	tmp41 = in7 + tmp31;
	tmp42 = in1 - tmp30;
	tmp43 = in7 - tmp31;

	tmp50 = FMUL(tmp40, OCOS_1_16) + FMUL(tmp41, OSIN_1_16);
	tmp51 = FMUL(tmp40, OSIN_1_16) - FMUL(tmp41, OCOS_1_16);
	tmp52 = FMUL(tmp42, OCOS_5_16) + FMUL(tmp43, OSIN_5_16);
	tmp53 = FMUL(tmp42, OSIN_5_16) - FMUL(tmp43, OCOS_5_16);

	DstPtr = SrcDst;
	*DstPtr = unfixh(tmp20 + tmp50);
	DstPtr += Stride;
	*DstPtr = unfixh(tmp21 + tmp53);
	DstPtr += Stride;
	*DstPtr = unfixh(tmp22 + tmp52);
	DstPtr += Stride;
	*DstPtr = unfixh(tmp23 + tmp51);
	DstPtr += Stride;
	*DstPtr = unfixh(tmp23 - tmp51);
	DstPtr += Stride;
	*DstPtr = unfixh(tmp22 - tmp52);
	DstPtr += Stride;
	*DstPtr = unfixh(tmp21 - tmp53);
	DstPtr += Stride;
	*DstPtr = unfixh(tmp20 - tmp50);
}


/**
**************************************************************************
*  Performs in-place IDCT of vector of 8 elements (used to access rows in shared memory).
*
* \param V8			[IN/OUT] - Pointer to the first two elements of vector
*  
* \return None
*/
__device__ void CUDAshortInplaceIDCT(unsigned int *V8)
{
	int in0, in1, in2, in3, in4, in5, in6, in7;
	int tmp10, tmp11, tmp12, tmp13;
	int tmp20, tmp21, tmp22, tmp23;
	int tmp30, tmp31;
	int tmp40, tmp41, tmp42, tmp43;
	int tmp50, tmp51, tmp52, tmp53;
	PackedShorts sh0, sh1, sh2, sh3;

	sh0.hInt = V8[0];
	sh1.hInt = V8[1];
	sh2.hInt = V8[2];
	sh3.hInt = V8[3];
	in0 = sh0.hShort1;
	in1 = sh0.hShort2;
	in2 = sh1.hShort1;
	in3 = sh1.hShort2;
	in4 = sh2.hShort1;
	in5 = sh2.hShort2;
	in6 = sh3.hShort1;
	in7 = sh3.hShort2;

	tmp10 = FMUL(in0 + in4, COS_1_4);
	tmp11 = FMUL(in0 - in4, COS_1_4);
	tmp12 = FMUL(in2, SIN_1_8) - FMUL(in6, COS_1_8);
	tmp13 = FMUL(in6, SIN_1_8) + FMUL(in2, COS_1_8);

	tmp20 = tmp10 + tmp13;
	tmp21 = tmp11 + tmp12;
	tmp22 = tmp11 - tmp12;
	tmp23 = tmp10 - tmp13;

	tmp30 = unfixo(FMUL(in3 + in5, COS_1_4));
	tmp31 = unfixo(FMUL(in3 - in5, COS_1_4));

	in1 <<= 2;
	in7 <<= 2;

	tmp40 = in1 + tmp30;
	tmp41 = in7 + tmp31;
	tmp42 = in1 - tmp30;
	tmp43 = in7 - tmp31;

	tmp50 = FMUL(tmp40, OCOS_1_16) + FMUL(tmp41, OSIN_1_16);
	tmp51 = FMUL(tmp40, OSIN_1_16) - FMUL(tmp41, OCOS_1_16);
	tmp52 = FMUL(tmp42, OCOS_5_16) + FMUL(tmp43, OSIN_5_16);
	tmp53 = FMUL(tmp42, OSIN_5_16) - FMUL(tmp43, OCOS_5_16);

	sh0.hShort1 = unfixh(tmp20 + tmp50);
	sh0.hShort2 = unfixh(tmp21 + tmp53);
	sh1.hShort1 = unfixh(tmp22 + tmp52);
	sh1.hShort2 = unfixh(tmp23 + tmp51);
	sh2.hShort1 = unfixh(tmp23 - tmp51);
	sh2.hShort2 = unfixh(tmp22 - tmp52);
	sh3.hShort1 = unfixh(tmp21 - tmp53);
	sh3.hShort2 = unfixh(tmp20 - tmp50);

	V8[0] = sh0.hInt;
	V8[1] = sh1.hInt;
	V8[2] = sh2.hInt;
	V8[3] = sh3.hInt;
}



/**
**************************************************************************
*  Performs 8x8 block-wise Forward Discrete Cosine Transform of the given 
*  image plane and outputs result to the array of coefficients. Short implementation.
*  This kernel is designed to process image by blocks of blocks8x8 that 
*  utilize maximum warps capacity, assuming that it is enough of 8 threads 
*  per block8x8.
*
* \param SrcDst						[OUT] - Coefficients plane
* \param ImgStride					[IN] - Stride of SrcDst
*  
* \return None
*/
__global__ void CUDAkernelShortDCT(short *SrcDst, int ImgStride)
{
	__shared__ short block[KERS_BLOCK_HEIGHT * KERS_SMEMBLOCK_STRIDE];

	register int reg1, reg2;

	//int OffsThreadInRow = FMUL(threadIdx.y, BLOCK_SIZE) + threadIdx.x;
	reg1 = threadIdx.y;
	reg1 <<= BLOCK_SIZE_LOG2;
	reg1 += threadIdx.x;
	int OffsThreadInRow = reg1;

	//int OffsThreadInCol = FMUL(threadIdx.z, BLOCK_SIZE);
	reg1 = threadIdx.z;
	reg1 <<= BLOCK_SIZE_LOG2;
	int OffsThreadInCol = reg1;

	int block_y_offs = OffsThreadInCol;
	
	//int OffsThrRowPermuted = bankID & 0xFFFFFFE0 | ((bankID << 1) | (bankID >> 4) & 0x1) & 0x1F;
	reg1 = OffsThreadInRow;
	reg1 &= 0xFFFFFFE0;
	int OffsThrRowPermuted = reg1;
	reg1 = OffsThreadInRow;
	reg1 <<= 1;
	reg2 = OffsThreadInRow;
	reg2 >>= 4;
	reg2 &= 0x1;
	reg1 |= reg2;
	reg1 &= 0x1F;
	OffsThrRowPermuted |= reg1;

	//SrcDst += FMUL(FMUL(blockIdx.y, KERS_BLOCK_HEIGHT) + OffsThreadInCol, ImgStride) + FMUL(blockIdx.x, KERS_BLOCK_WIDTH) + FMUL(OffsThreadInRow, 2);
	reg1 = blockIdx.y;
	reg1 <<= KERS_BH_LOG2;
	reg1 += OffsThreadInCol;
	reg1 *= ImgStride;
	reg2 = blockIdx.x;
	reg2 <<= KERS_BW_LOG2;
	reg1 += reg2;
	reg2 = OffsThreadInRow;
	reg2 <<= 1;
	reg1 += reg2;
	SrcDst += reg1;
	
	//short *bl_ptr = block + FMUL(block_y_offs, KERS_SMEMBLOCK_STRIDE) + FMUL(OffsThreadInRow, 2);
	reg1 = block_y_offs;
	reg1 = FMUL(reg1, KERS_SMEMBLOCK_STRIDE);
	reg2 = OffsThreadInRow;
	reg2 <<= 1;
	reg1 += reg2;
	short *bl_ptr = block + reg1;

	//load data to shared memory (only first half of threads in each row performs data moving (each thread moves 2 shorts)
	if (OffsThreadInRow < KERS_BLOCK_WIDTH_HALF)
	{
		*((int *)bl_ptr) = *((int *)SrcDst);
		SrcDst += ImgStride;
		bl_ptr += KERS_SMEMBLOCK_STRIDE;

		*((int *)bl_ptr) = *((int *)SrcDst);
		SrcDst += ImgStride;
		bl_ptr += KERS_SMEMBLOCK_STRIDE;

		*((int *)bl_ptr) = *((int *)SrcDst);
		SrcDst += ImgStride;
		bl_ptr += KERS_SMEMBLOCK_STRIDE;

		*((int *)bl_ptr) = *((int *)SrcDst);
		SrcDst += ImgStride;
		bl_ptr += KERS_SMEMBLOCK_STRIDE;

		*((int *)bl_ptr) = *((int *)SrcDst);
		SrcDst += ImgStride;
		bl_ptr += KERS_SMEMBLOCK_STRIDE;

		*((int *)bl_ptr) = *((int *)SrcDst);
		SrcDst += ImgStride;
		bl_ptr += KERS_SMEMBLOCK_STRIDE;

		*((int *)bl_ptr) = *((int *)SrcDst);
		SrcDst += ImgStride;
		bl_ptr += KERS_SMEMBLOCK_STRIDE;

		*((int *)bl_ptr) = *((int *)SrcDst);
	}

	__syncthreads();
	CUDAshortInplaceDCT(block + OffsThreadInCol * KERS_SMEMBLOCK_STRIDE + OffsThrRowPermuted, KERS_SMEMBLOCK_STRIDE);
	__syncthreads();
	CUDAshortInplaceDCT((unsigned int *)(block + OffsThreadInRow * KERS_SMEMBLOCK_STRIDE + OffsThreadInCol));
	__syncthreads();

	//store data to global memory (only first half of threads in each row performs data moving (each thread moves 2 shorts)
	if (OffsThreadInRow < KERS_BLOCK_WIDTH_HALF)
	{
		*((int *)SrcDst) = *((int *)bl_ptr);
		SrcDst -= ImgStride;
		bl_ptr -= KERS_SMEMBLOCK_STRIDE;

		*((int *)SrcDst) = *((int *)bl_ptr);
		SrcDst -= ImgStride;
		bl_ptr -= KERS_SMEMBLOCK_STRIDE;

		*((int *)SrcDst) = *((int *)bl_ptr);
		SrcDst -= ImgStride;
		bl_ptr -= KERS_SMEMBLOCK_STRIDE;

		*((int *)SrcDst) = *((int *)bl_ptr);
		SrcDst -= ImgStride;
		bl_ptr -= KERS_SMEMBLOCK_STRIDE;

		*((int *)SrcDst) = *((int *)bl_ptr);
		SrcDst -= ImgStride;
		bl_ptr -= KERS_SMEMBLOCK_STRIDE;

		*((int *)SrcDst) = *((int *)bl_ptr);
		SrcDst -= ImgStride;
		bl_ptr -= KERS_SMEMBLOCK_STRIDE;

		*((int *)SrcDst) = *((int *)bl_ptr);
		SrcDst -= ImgStride;
		bl_ptr -= KERS_SMEMBLOCK_STRIDE;

		*((int *)SrcDst) = *((int *)bl_ptr);
	}
}


/**
**************************************************************************
*  Performs 8x8 block-wise Inverse Discrete Cosine Transform of the given 
*  image plane and outputs result to the array of coefficients. Short implementation.
*  This kernel is designed to process image by blocks of blocks8x8 that 
*  utilize maximum warps capacity, assuming that it is enough of 8 threads 
*  per block8x8.
*
* \param SrcDst						[OUT] - Coefficients plane
* \param ImgStride					[IN] - Stride of SrcDst
*  
* \return None
*/
__global__ void CUDAkernelShortIDCT(short *SrcDst, int ImgStride)
{
	__shared__ short block[KERS_BLOCK_HEIGHT * KERS_SMEMBLOCK_STRIDE];

	register int reg1, reg2;

	//int OffsThreadInRow = FMUL(threadIdx.y, BLOCK_SIZE) + threadIdx.x;
	reg1 = threadIdx.y;
	reg1 <<= BLOCK_SIZE_LOG2;
	reg1 += threadIdx.x;
	int OffsThreadInRow = reg1;

	//int OffsThreadInCol = FMUL(threadIdx.z, BLOCK_SIZE);
	reg1 = threadIdx.z;
	reg1 <<= BLOCK_SIZE_LOG2;
	int OffsThreadInCol = reg1;

	int block_y_offs = OffsThreadInCol;

	//int OffsThrRowPermuted = bankID & 0xFFFFFFE0 | ((bankID << 1) | (bankID >> 4) & 0x1) & 0x1F;
	reg1 = OffsThreadInRow;
	reg1 &= 0xFFFFFFE0;
	int OffsThrRowPermuted = reg1;
	reg1 = OffsThreadInRow;
	reg1 <<= 1;
	reg2 = OffsThreadInRow;
	reg2 >>= 4;
	reg2 &= 0x1;
	reg1 |= reg2;
	reg1 &= 0x1F;
	OffsThrRowPermuted |= reg1;

	//SrcDst += FMUL(FMUL(blockIdx.y, KERS_BLOCK_HEIGHT) + OffsThreadInCol, ImgStride) + FMUL(blockIdx.x, KERS_BLOCK_WIDTH) + FMUL(OffsThreadInRow, 2);
	reg1 = blockIdx.y;
	reg1 <<= KERS_BH_LOG2;
	reg1 += OffsThreadInCol;
	reg1 = FMUL(reg1, ImgStride);
	reg2 = blockIdx.x;
	reg2 <<= KERS_BW_LOG2;
	reg1 += reg2;
	reg2 = OffsThreadInRow;
	reg2 <<= 1;
	reg1 += reg2;
	SrcDst += reg1;

	//short *bl_ptr = block + FMUL(block_y_offs, KERS_SMEMBLOCK_STRIDE) + FMUL(OffsThreadInRow, 2);
	reg1 = block_y_offs;
	reg1 = FMUL(reg1, KERS_SMEMBLOCK_STRIDE);
	reg2 = OffsThreadInRow;
	reg2 <<= 1;
	reg1 += reg2;
	short *bl_ptr = block + reg1;

	//load data to shared memory (only first half of threads in each row performs data moving (each thread moves 2 shorts)
	if (OffsThreadInRow < KERS_BLOCK_WIDTH_HALF)
	{
		*((int *)bl_ptr) = *((int *)SrcDst);
		SrcDst += ImgStride;
		bl_ptr += KERS_SMEMBLOCK_STRIDE;

		*((int *)bl_ptr) = *((int *)SrcDst);
		SrcDst += ImgStride;
		bl_ptr += KERS_SMEMBLOCK_STRIDE;

		*((int *)bl_ptr) = *((int *)SrcDst);
		SrcDst += ImgStride;
		bl_ptr += KERS_SMEMBLOCK_STRIDE;

		*((int *)bl_ptr) = *((int *)SrcDst);
		SrcDst += ImgStride;
		bl_ptr += KERS_SMEMBLOCK_STRIDE;

		*((int *)bl_ptr) = *((int *)SrcDst);
		SrcDst += ImgStride;
		bl_ptr += KERS_SMEMBLOCK_STRIDE;

		*((int *)bl_ptr) = *((int *)SrcDst);
		SrcDst += ImgStride;
		bl_ptr += KERS_SMEMBLOCK_STRIDE;

		*((int *)bl_ptr) = *((int *)SrcDst);
		SrcDst += ImgStride;
		bl_ptr += KERS_SMEMBLOCK_STRIDE;

		*((int *)bl_ptr) = *((int *)SrcDst);
	}

	__syncthreads();
	CUDAshortInplaceIDCT(block + OffsThreadInCol * KERS_SMEMBLOCK_STRIDE + OffsThrRowPermuted, KERS_SMEMBLOCK_STRIDE);
	__syncthreads();
	CUDAshortInplaceIDCT((unsigned int *)(block + OffsThreadInRow * KERS_SMEMBLOCK_STRIDE + OffsThreadInCol));
	__syncthreads();

	//store data to global memory (only first half of threads in each row performs data moving (each thread moves 2 shorts)
	if (OffsThreadInRow < KERS_BLOCK_WIDTH_HALF)
	{
		*((int *)SrcDst) = *((int *)bl_ptr);
		SrcDst -= ImgStride;
		bl_ptr -= KERS_SMEMBLOCK_STRIDE;

		*((int *)SrcDst) = *((int *)bl_ptr);
		SrcDst -= ImgStride;
		bl_ptr -= KERS_SMEMBLOCK_STRIDE;

		*((int *)SrcDst) = *((int *)bl_ptr);
		SrcDst -= ImgStride;
		bl_ptr -= KERS_SMEMBLOCK_STRIDE;

		*((int *)SrcDst) = *((int *)bl_ptr);
		SrcDst -= ImgStride;
		bl_ptr -= KERS_SMEMBLOCK_STRIDE;

		*((int *)SrcDst) = *((int *)bl_ptr);
		SrcDst -= ImgStride;
		bl_ptr -= KERS_SMEMBLOCK_STRIDE;

		*((int *)SrcDst) = *((int *)bl_ptr);
		SrcDst -= ImgStride;
		bl_ptr -= KERS_SMEMBLOCK_STRIDE;

		*((int *)SrcDst) = *((int *)bl_ptr);
		SrcDst -= ImgStride;
		bl_ptr -= KERS_SMEMBLOCK_STRIDE;

		*((int *)SrcDst) = *((int *)bl_ptr);
	}
}