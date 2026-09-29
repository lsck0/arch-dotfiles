/*
 * Stand-in for OpenMPI 4's libmpi_cxx.so.40.
 *
 * The torch ROCm wheels from wheels.vllm.ai are built on Ubuntu against OpenMPI 4 and list libmpi_cxx.so.40 as
 * NEEDED. OpenMPI 5 (Arch) removed the C++ bindings, so `import torch` fails in the loader. torch only references the
 * symbols below, through header-inlined MPI C++ classes, and never calls them since vllm does not use the MPI
 * backend. Delete this once the wheels are built against OpenMPI 5 or without MPI.
 */

#include <stdio.h>
#include <stdlib.h>

static void mpi_cxx_stub_abort(const char *name) {
    fprintf(stderr, "libmpi_cxx stub: %s called, torch needs real OpenMPI 4 C++ bindings\n", name);
    abort();
}

/* MPI::Comm::Comm(), base constructor; empty in OpenMPI 4 as well. */
void _ZN3MPI4CommC2Ev(void *self) {
    (void)self;
}

/* MPI::Win::Free() */
void _ZN3MPI3Win4FreeEv(void *self) {
    (void)self;
    mpi_cxx_stub_abort("MPI::Win::Free");
}

/* MPI::Datatype::Free() */
void _ZN3MPI8Datatype4FreeEv(void *self) {
    (void)self;
    mpi_cxx_stub_abort("MPI::Datatype::Free");
}

/* MPI::Op::Init trampoline, lived in libmpi_cxx in OpenMPI 4. */
void ompi_mpi_cxx_op_intercept(void *invec, void *outvec, int *len, void *datatype, void *fn) {
    (void)invec, (void)outvec, (void)len, (void)datatype, (void)fn;
    mpi_cxx_stub_abort("ompi_mpi_cxx_op_intercept");
}

/* MPI::Op::Init registration, lived in libmpi in OpenMPI 4 and was removed in 5. */
void ompi_op_set_cxx_callback(void *op, void *fn) {
    (void)op, (void)fn;
    mpi_cxx_stub_abort("ompi_op_set_cxx_callback");
}
