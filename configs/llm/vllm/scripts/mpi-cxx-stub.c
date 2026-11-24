/* stub for openmpi 4 libmpi_cxx.so.40 that the rocm torch wheels link; arch has openmpi 5 */

#include <stdio.h>
#include <stdlib.h>

static void mpi_cxx_stub_abort(const char *name) {
    fprintf(stderr, "libmpi_cxx stub: %s called, torch needs real OpenMPI 4 C++ bindings\n", name);
    abort();
}

/* MPI::Comm::Comm(), empty upstream too */
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

/* MPI::Op::Init trampoline */
void ompi_mpi_cxx_op_intercept(void *invec, void *outvec, int *len, void *datatype, void *fn) {
    (void)invec, (void)outvec, (void)len, (void)datatype, (void)fn;
    mpi_cxx_stub_abort("ompi_mpi_cxx_op_intercept");
}

/* MPI::Op::Init registration */
void ompi_op_set_cxx_callback(void *op, void *fn) {
    (void)op, (void)fn;
    mpi_cxx_stub_abort("ompi_op_set_cxx_callback");
}
