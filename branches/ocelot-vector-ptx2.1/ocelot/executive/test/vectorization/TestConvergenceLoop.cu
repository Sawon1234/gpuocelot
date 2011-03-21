/*!
	\file TestConvergenceLoop.cu
	\date 17 February 2011
	\author Andrew Kerr <arkerr@gatech.edu>
	\brief Demonstrates convergent execution
*/

// Standard Library Includes
#include <stdio.h>
#include <math.h>

/////////////////////////////////////////////////////////////////////////////////////////////////

/*!

*/
extern "C" __global__ void convergenceWithLoop(float *A, int P) {
	int i = threadIdx.x;
	float f = i * 2.0f + 1.0f;;
	for (int p = 0; p < P; p++) {
		f *= 1.25f - 2.0f;
	}
	A[i] = f;
}

/*!
	\brief loop with divergent control flow
*/
extern "C" __global__ void loopEarlyExit(float *A, float dt) {
	int i = threadIdx.x;
	float f = A[i];
	for (int p = 0; p < i + 1; p++) {
		f += dt;
	}
	A[i] = f;
}

static float expectedValue(int n,  int P) {
	int i = n;
	float f = i * 2.0f + 1.0f;;
	for (int p = 0; p < P; p++) {
		f *= 1.25f - 2.0f;
	}
	return f;
}

static int testConvergenceWithLoop() {
	const int N = 4;
	const int P = 3;
	float *A_host, *A_device;
	size_t bytes = N * sizeof(float);
	
	A_host = (float *)malloc(bytes);
	cudaMalloc((void **)&A_device, bytes);
	
	for (int i = 0; i < N; i++) {
		A_host[i] = (float)(i+1);
	}
	cudaMemcpy(A_device, A_host, bytes, cudaMemcpyHostToDevice);
	
	convergenceWithLoop<<< dim3(1,1), dim3(N, 1, 1) >>>(A_device, P);
	
	cudaMemcpy(A_host, A_device, bytes, cudaMemcpyDeviceToHost);
	
	int errors = 0;
	for (int i = 0; (errors < 5) && i < N; i++) {
		float expected = expectedValue(i, P);
		float got = A_host[i];
		if (fabs(expected - got) > 0.001f) {
			++errors;
			printf("error 1 [%d] - expected: %f, got %f\n", i, expected, got);
		}
	}
	
	cudaFree(A_device);
	free(A_host);
	return errors;
}

static int testLoopEarlyExit() {
	const int N = 8;
	float *A_host, *A_gpu;
	
	size_t bytes = sizeof(float)*N;
	cudaMalloc((void **)&A_gpu, bytes);
	A_host = (float *)malloc(bytes);
	
	for (int i = 0; i < N; i++) {
		A_host[i] = 2.0f * (float)i / (float)(N-1);
	}
	
	cudaMemcpy(A_gpu, A_host, bytes, cudaMemcpyHostToDevice);
	
	float dt = 0.25f;
	dim3 grid(1,1);
	dim3 block(N,1,1);
	
	loopEarlyExit<<< grid, block >>>(A_gpu, dt);

	cudaMemcpy(A_host, A_gpu, bytes, cudaMemcpyDeviceToHost);
	int errors = 0;
	for (int i = 0; errors < 5 && i < N; i++) {
		float got = A_host[i];
		float expected = 2.0f * (float)i / (float)(N-1) + i * dt;
		printf("ERROR 2 [%d] - expected: %f, got: %f\n", i, expected, got);
		++errors;
	}
	
	free(A_host);
	cudaFree(A_gpu);
	
	return errors;
}

/////////////////////////////////////////////////////////////////////////////////////////////////

int main( int argc, char** argv )
{
	int errors = 0;
	if (!errors) {
		errors += testConvergenceWithLoop();
	}
	if (!errors) {
		errors += testLoopEarlyExit();
	}

	printf("Pass/Fail : %s\n", (errors ? "Fail":"Pass"));

	return 0;
}