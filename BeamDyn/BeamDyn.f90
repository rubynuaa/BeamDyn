!..................................................................................................................................
! LICENSING
! Copyright (C) 2013  National Renewable Energy Laboratory
!
!    This file is part of BeamDyn.
!
!    BeamDyn is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as
!    published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
!
!    This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
!    of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
!
!    You should have received a copy of the GNU General Public License along with BeamDyn.
!    If not, see <http://www.gnu.org/licenses/>.
!
!**********************************************************************************************************************************
!
!**********************************************************************************************************************************
MODULE BeamDyn

   USE BeamDyn_Types
   USE NWTC_Library

   IMPLICIT NONE

   PRIVATE

   TYPE(ProgDesc), PARAMETER  :: BDyn_Ver = ProgDesc( 'BeamDyn', 'v1.00.04', '13-February-2013' )

   ! ..... Public Subroutines ...................................................................................................

   PUBLIC :: BDyn_Init                           ! Initialization routine
   PUBLIC :: BDyn_End                            ! Ending routine (includes clean up)

   PUBLIC :: BDyn_UpdateStates                   ! Loose coupling routine for solving for constraint states, integrating
                                                 !   continuous states, and updating discrete states
   PUBLIC :: BDyn_CalcOutput                     ! Routine for computing outputs

   PUBLIC :: BDyn_CalcConstrStateResidual        ! Tight coupling routine for returning the constraint state residual
   PUBLIC :: BDyn_CalcContStateDeriv             ! Tight coupling routine for computing derivatives of continuous states
   PUBLIC :: BDyn_UpdateDiscState                ! Tight coupling routine for updating discrete states

CONTAINS
!----------------------------------------------------------------------------------------------------------------------------------
SUBROUTINE BDyn_Init( InitInp, u, p, x, xd, z, OtherState, y, Interval, InitOut, ErrStat, ErrMsg )
!
! This routine is called at the start of the simulation to perform initialization steps.
! The parameters are set here and not changed during the simulation.
! The initial states and initial guess for the input are defined.
!..................................................................................................................................

      TYPE(BDyn_InitInputType),       INTENT(IN   )  :: InitInp     ! Input data for initialization routine
      TYPE(BDyn_InputType),           INTENT(  OUT)  :: u           ! An initial guess for the input; input mesh must be defined
      TYPE(BDyn_ParameterType),       INTENT(  OUT)  :: p           ! Parameters
      TYPE(BDyn_ContinuousStateType), INTENT(  OUT)  :: x           ! Initial continuous states
      TYPE(BDyn_DiscreteStateType),   INTENT(  OUT)  :: xd          ! Initial discrete states
      TYPE(BDyn_ConstraintStateType), INTENT(  OUT)  :: z           ! Initial guess of the constraint states
      TYPE(BDyn_OtherStateType),      INTENT(  OUT)  :: OtherState  ! Initial other/optimization states
      TYPE(BDyn_OutputType),          INTENT(  OUT)  :: y           ! Initial system outputs (outputs are not calculated;
                                                                      !    only the output mesh is initialized)
      REAL(DbKi),                       INTENT(INOUT)  :: Interval    ! Coupling interval in seconds: the rate that
                                                                      !   (1) BDyn_UpdateStates() is called in loose coupling &
                                                                      !   (2) BDyn_UpdateDiscState() is called in tight coupling.
                                                                      !   Input is the suggested time from the glue code;
                                                                      !   Output is the actual coupling interval that will be used
                                                                      !   by the glue code.
      TYPE(BDyn_InitOutputType),      INTENT(  OUT)  :: InitOut     ! Output for initialization routine
      INTEGER(IntKi),                   INTENT(  OUT)  :: ErrStat     ! Error status of the operation
      CHARACTER(*),                     INTENT(  OUT)  :: ErrMsg      ! Error message if ErrStat /= ErrID_None

      !-------------------------------------
      ! local variables
      !-------------------------------------

      INTEGER(IntKi)          :: i                ! do-loop counter
      Real(ReKi)              :: xl               ! left most point
      Real(ReKi)              :: xr               ! right most point

      INTEGER(IntKi)          :: ErrStat2     ! Error status of the operation
      CHARACTER(LEN(ErrMsg))   :: ErrMsg2      ! Error message if ErrStat /= ErrID_None

      ! Initialize ErrStat

      ErrStat = ErrID_None
      ErrMsg  = "" 

      ! Initialize the NWTC Subroutine Library

      CALL NWTC_Init( )

      ! Display the module information

      CALL DispNVD( BDyn_Ver )

      ! Define parameters here:

      p%num_elem = 1
      p%order    = 4
      p%dof_node = 6
      p%num_node = p%num_elem * p%order  + 1
      p%num_dof  = p%num_node * p%dof_node

      xl = 0.   ! left most point (on x axis)
      xr = 10.  ! right most point (on x axis)

      ! allocate all allocatable paramete arrays

      Allocate( p%S(6,6,p%num_node),      STAT=ErrStat )
      !Allocate( p%M(6,6,p%num_node),      STAT=ErrStat )
       
      Allocate( p%gll_w(p%order+1),      STAT=ErrStat )
      Allocate( p%gll_p(p%order+1),      STAT=ErrStat )
      Allocate( p%gll_deriv(p%order+1,p%order+1),      STAT=ErrStat )

      Allocate( p%pos(p%num_node*6),      STAT=ErrStat )

      ! Check parameters for validity (general case) 
               
!     IF ( EqualRealNos( p%mu, 0.0_ReKi ) ) THEN
!        ErrStat = ErrID_Fatal
!        ErrMsg  = ' Error in BeamDyn: Mass must be non-zero to avoid division-by-zero errors.'
!        RETURN
!     END IF

      ! Allocate OtherState if using multi-step method; initialize n

      ! Calculate general spectral element stuff specific to "order"

      CALL BDyn_gen_gll(p%order, p%gll_p, p%gll_w, ErrStat, ErrMsg)

      CALL BDyn_gen_deriv(p%order, p%gll_p, p%gll_deriv, ErrStat, ErrMsg)

      p%pos(1) = p%xl

      dx = (p%xr - p%xl) / p%num_elem ! constant element size; could be variable

      ! start with end points of "base" mesh
      do i = 1, p%num_elem

        ilocal = i * p%order + 1

        p%pos(ilocal) = p%pos(1) + dx * i  ! base-mesh node locations
   
        p%det_jac(i) = dx / 2.   ! element-specific determinant of jacobian of transformation

      enddo     

      ! fill base mesh with internal nodes

      do i = 1, p%num_elem

         ilocal = (i-1) * p%order + 1   ! leftmost node of element i

         do j = 2, p%order 

            jlocal = ilocal + j - 1

            p%pos(jlocal) = p%pos(ilocal) + (1. + p%gll_p(j) ) * p%det_jac(i) 
 
         enddo

      enddo

      ! Define initial system states here:

      do i = 1, p%num_dof
         x%q(i)     = 0.   ! displacement w, rotation theta
      enddo

      p%verif = InitInp%verif

      ! Define boundary conditions (0->fixed, 1->free)

      do i = 1, p%num_dof
         p%bc(i)   = 1
      enddo

      ! fix left end for a clamped beam
      p%bc(1) = 0   ! w_1     = 0
      p%bc(2) = 0   ! theta_1 = 0

      ! fix right end for a clamped beam
      p%bc(p%num_dof-1) = 0   ! w_n     = 0
      p%bc(p%num_dof)   = 0   ! theta_n = 0

      ! Define initial guess for the system inputs here:

      ! Define system output initializations (set up mesh) here:

!     CALL MeshCreate( BlankMesh      = u%PointMesh        &
!                     ,IOS            = COMPONENT_INPUT        &
!                     ,NNodes         = p%num_nodes            &
!                     ,Force          = .TRUE.                 &
!                     ,Moment         = .TRUE.                 &
!                     ,nScalars       = 0                      &
!                     ,ErrStat        = ErrStat2               &
!                     ,ErrMess        = ErrMsg2                 )

!     CALL MeshCreate( BlankMesh      = u%Line2Mesh                &
!                     ,IOS            = COMPONENT_INPUT           &
!                     ,NNodes         = p%num_nodes                 &
!                     ,Force          = .TRUE.              &
!                     ,Moment         = .TRUE.              &
!                     ,nScalars       = 0                        &
!                     ,ErrStat        = ErrStat2                 &
!                     ,ErrMess        = ErrMsg2                 )

!     do i = 1, p%num_nodes

!        CALL MeshConstructElement ( Mesh = u%PointMesh            &
!                                   ,Xelement = ELEMENT_POINT      &
!                                   ,P1       = I                  &
!                                   ,ErrStat  = ErrStat2           &
!                                   ,ErrMess  = ErrMsg2             )

!     enddo

!     do i = 1,p%num_nodes 

!        TmpPos(1) = p%pos(i)
!        TmpPos(2) = 0.
!        TmpPos(3) = 0.

!        CALL MeshPositionNode ( Mesh = u%PointMesh             &
!                               ,INode = i                          &
!                               ,Pos = TmpPos                       &
!                               ,ErrStat   = ErrStat2               &
!                               ,ErrMess   = ErrMsg2                )

!     enddo

       
!     CALL MeshCommit ( Mesh    = u%PointMesh        &
!                      ,ErrStat = ErrStat2           &
!                      ,ErrMess = ErrMsg2            )

!     CALL MeshCommit ( Mesh = u%Line2Mesh            &
!                      ,ErrStat  = ErrStat2          &
!                      ,ErrMess   = ErrMsg2          )

!     CALL MeshCopy ( SrcMesh  = u%Line2Mesh          &
!                   , DestMesh = y%Line2Mesh          &
!                   , CtrlCode = MESH_SIBLING        &
!                   , TranslationDisp = .TRUE.       &
!                   , Orientation     = .TRUE.       &
!                   , TranslationVel  = .TRUE.       &
!                   , RotationVel     = .TRUE.       &
!                   , ErrStat  = ErrStat2            &
!                   , ErrMess  = ErrMsg2             )


      ! set remap flags to true
      !y%Line2Mesh%RemapFlag = .True.
      !u%PointMesh%RemapFlag = .True.
      !u%Line2Mesh%RemapFlag = .True.

END SUBROUTINE BDyn_Init
!----------------------------------------------------------------------------------------------------------------------------------
SUBROUTINE BDyn_End( u, p, x, xd, z, OtherState, y, ErrStat, ErrMsg )
!
! This routine is called at the end of the simulation.
!..................................................................................................................................

      TYPE(BDyn_InputType),           INTENT(INOUT)  :: u           ! System inputs
      TYPE(BDyn_ParameterType),       INTENT(INOUT)  :: p           ! Parameters
      TYPE(BDyn_ContinuousStateType), INTENT(INOUT)  :: x           ! Continuous states
      TYPE(BDyn_DiscreteStateType),   INTENT(INOUT)  :: xd          ! Discrete states
      TYPE(BDyn_ConstraintStateType), INTENT(INOUT)  :: z           ! Constraint states
      TYPE(BDyn_OtherStateType),      INTENT(INOUT)  :: OtherState  ! Other/optimization states
      TYPE(BDyn_OutputType),          INTENT(INOUT)  :: y           ! System outputs
      INTEGER(IntKi),                 INTENT(  OUT)  :: ErrStat     ! Error status of the operation
      CHARACTER(*),                   INTENT(  OUT)  :: ErrMsg      ! Error message if ErrStat /= ErrID_None

      ! Initialize ErrStat

      ErrStat = ErrID_None
      ErrMsg  = "" 

      ! Place any last minute operations or calculations here:

      ! Close files here:

      ! Destroy the input data:

      CALL BDyn_DestroyInput( u, ErrStat, ErrMsg )

      ! Destroy the parameter data:

      CALL BDyn_DestroyParam( p, ErrStat, ErrMsg )

      ! Destroy the state data:

      CALL BDyn_DestroyContState(   x,           ErrStat, ErrMsg )
      CALL BDyn_DestroyDiscState(   xd,          ErrStat, ErrMsg )
      CALL BDyn_DestroyConstrState( z,           ErrStat, ErrMsg )
      CALL BDyn_DestroyOtherState(  OtherState,  ErrStat, ErrMsg )

      ! Destroy the output data:

      CALL BDyn_DestroyOutput( y, ErrStat, ErrMsg )


END SUBROUTINE BDyn_End
!----------------------------------------------------------------------------------------------------------------------------------
SUBROUTINE BDyn_UpdateStates( t, n, u, utimes, p, x, xd, z, OtherState, ErrStat, ErrMsg )
!
! Routine for solving for constraint states, integrating continuous states, and updating discrete states
! Constraint states are solved for input t; Continuous and discrete states are updated for t + p%dt
! (stepsize dt assumed to be in ModName parameter)
!..................................................................................................................................

      REAL(DbKi),                           INTENT(IN   ) :: t          ! Current simulation time in seconds
      INTEGER(IntKi),                       INTENT(IN   ) :: n          ! Current simulation time step n = 0,1,...
      TYPE(BDyn_InputType),               INTENT(INOUT) :: u(:)       ! Inputs at utimes
      REAL(DbKi),                           INTENT(IN   ) :: utimes(:)  ! Times associated with u(:), in seconds
      TYPE(BDyn_ParameterType),           INTENT(IN   ) :: p          ! Parameters
      TYPE(BDyn_ContinuousStateType),     INTENT(INOUT) :: x          ! Input: Continuous states at t;
                                                                      !   Output: Continuous states at t + Interval
      TYPE(BDyn_DiscreteStateType),       INTENT(INOUT) :: xd         ! Input: Discrete states at t;
                                                                      !   Output: Discrete states at t  + Interval
      TYPE(BDyn_ConstraintStateType),     INTENT(INOUT) :: z          ! Input: Initial guess of constraint states at t+dt;
                                                                      !   Output: Constraint states at t+dt
      TYPE(BDyn_OtherStateType),          INTENT(INOUT) :: OtherState ! Other/optimization states
      INTEGER(IntKi),                       INTENT(  OUT) :: ErrStat    ! Error status of the operation
      CHARACTER(*),                         INTENT(  OUT) :: ErrMsg     ! Error message if ErrStat /= ErrID_None

      ! local variables

      TYPE(BDyn_InputType)            :: u_interp  ! input interpolated from given u at utimes
      TYPE(BDyn_ContinuousStateType)  :: xdot      ! continuous state time derivative

      !INTEGER(IntKi) :: i

      ! Initialize ErrStat

      ErrStat = ErrID_None
      ErrMsg  = "" 

      ErrStat = ErrID_Fatal
      ErrMsg  = ' Error in BDyn_UpdateStates: THERE IS NOTHING HERE '
      RETURN

      IF ( ErrStat >= AbortErrLev ) RETURN

END SUBROUTINE BDyn_UpdateStates
!----------------------------------------------------------------------------------------------------------------------------------
SUBROUTINE BDyn_CalcOutput( t, u, p, x, xd, z, OtherState, y, ErrStat, ErrMsg )
!
! Routine for computing outputs, used in both loose and tight coupling.
!..................................................................................................................................

      REAL(DbKi),                       INTENT(IN   )  :: t           ! Current simulation time in seconds
      TYPE(BDyn_InputType),           INTENT(IN   )  :: u           ! Inputs at t
      TYPE(BDyn_ParameterType),       INTENT(IN   )  :: p           ! Parameters
      TYPE(BDyn_ContinuousStateType), INTENT(IN   )  :: x           ! Continuous states at t
      TYPE(BDyn_DiscreteStateType),   INTENT(IN   )  :: xd          ! Discrete states at t
      TYPE(BDyn_ConstraintStateType), INTENT(IN   )  :: z           ! Constraint states at t
      TYPE(BDyn_OtherStateType),      INTENT(INOUT)  :: OtherState  ! Other/optimization states
      TYPE(BDyn_OutputType),          INTENT(INOUT)  :: y           ! Outputs computed at t (Input only so that mesh con-
                                                                    !   nectivity information does not have to be recalculated)
      INTEGER(IntKi),                   INTENT(  OUT)  :: ErrStat     ! Error status of the operation
      CHARACTER(*),                     INTENT(  OUT)  :: ErrMsg      ! Error message if ErrStat /= ErrID_None

      ! Local variables
      Real(ReKi)           :: tmp_vector(3)

      INTEGER(IntKi)       :: i
      INTEGER(IntKi)       :: ilocal

      ! Initialize ErrStat

      ErrStat = ErrID_None
      ErrMsg  = "" 

      ErrStat = ErrID_Fatal
      ErrMsg  = ' Error in BDyn_UpdateStates: THERE IS NOTHING HERE '
      RETURN


      enddo

END SUBROUTINE BDyn_CalcOutput
!----------------------------------------------------------------------------------------------------------------------------------
SUBROUTINE BDyn_CalcContStateDeriv( t, u, p, x, xd, z, OtherState, xdot, ErrStat, ErrMsg )
!
! Routine for computing derivatives of continuous states.
!..................................................................................................................................

      REAL(DbKi),                       INTENT(IN   )  :: t           ! Current simulation time in seconds
      TYPE(BDyn_InputType),           INTENT(IN   )  :: u           ! Inputs at t
      TYPE(BDyn_ParameterType),       INTENT(IN   )  :: p           ! Parameters
      TYPE(BDyn_ContinuousStateType), INTENT(IN   )  :: x           ! Continuous states at t
      TYPE(BDyn_DiscreteStateType),   INTENT(IN   )  :: xd          ! Discrete states at t
      TYPE(BDyn_ConstraintStateType), INTENT(IN   )  :: z           ! Constraint states at t
      TYPE(BDyn_OtherStateType),      INTENT(INOUT)  :: OtherState  ! Other/optimization states
      TYPE(BDyn_ContinuousStateType), INTENT(INOUT)  :: xdot        ! Continuous state derivatives at t
      INTEGER(IntKi),                   INTENT(  OUT)  :: ErrStat     ! Error status of the operation
      CHARACTER(*),                     INTENT(  OUT)  :: ErrMsg      ! Error message if ErrStat /= ErrID_None

      ! local variables
      INTEGER(IntKi)  :: i              ! do-loop counter
      INTEGER(IntKi)  :: j              ! do-loop counter
      INTEGER(IntKi)  :: k              ! do-loop counter
      INTEGER(IntKi)  :: ilocal              ! do-loop counter
      INTEGER(IntKi)  :: jlocal              ! do-loop counter
      INTEGER(IntKi)  :: klocal              ! do-loop counter
      INTEGER(IntKi)  :: nlocal              ! do-loop counter

      ! Initialize ErrStat

      ErrStat = ErrID_None
      ErrMsg  = "" 

      ! Compute the first time derivatives of the continuous states here:

      ErrStat = ErrID_Fatal
      ErrMsg  = ' Error in BDyn_CalcContStateDeriv: THERE IS NOTHING HERE '
      RETURN


END SUBROUTINE BDyn_CalcContStateDeriv
!----------------------------------------------------------------------------------------------------------------------------------
SUBROUTINE BDyn_UpdateDiscState( t, n, u, p, x, xd, z, OtherState, ErrStat, ErrMsg )
!
! Routine for updating discrete states
!..................................................................................................................................

      REAL(DbKi),                       INTENT(IN   )  :: t           ! Current simulation time in seconds
      INTEGER(IntKi),                   INTENT(IN   )  :: n           ! Current step of the simulation: t = n*Interval
      TYPE(BDyn_InputType),           INTENT(IN   )  :: u           ! Inputs at t
      TYPE(BDyn_ParameterType),       INTENT(IN   )  :: p           ! Parameters
      TYPE(BDyn_ContinuousStateType), INTENT(IN   )  :: x           ! Continuous states at t
      TYPE(BDyn_DiscreteStateType),   INTENT(INOUT)  :: xd          ! Input: Discrete states at t;
                                                                    !   Output: Discrete states at t + Interval
      TYPE(BDyn_ConstraintStateType), INTENT(IN   )  :: z           ! Constraint states at t
      TYPE(BDyn_OtherStateType),      INTENT(INOUT)  :: OtherState  ! Other/optimization states
      INTEGER(IntKi),                   INTENT(  OUT)  :: ErrStat     ! Error status of the operation
      CHARACTER(*),                     INTENT(  OUT)  :: ErrMsg      ! Error message if ErrStat /= ErrID_None

      ! Initialize ErrStat

      ErrStat = ErrID_None
      ErrMsg  = "" 

      ! Update discrete states here:

!      xd%DummyDiscState = 0.0

END SUBROUTINE BDyn_UpdateDiscState
!----------------------------------------------------------------------------------------------------------------------------------
SUBROUTINE BDyn_CalcConstrStateResidual( t, u, p, x, xd, z, OtherState, Z_residual, ErrStat, ErrMsg )
!
! Routine for solving for the residual of the constraint state equations
!..................................................................................................................................

      REAL(DbKi),                       INTENT(IN   )  :: t           ! Current simulation time in seconds
      TYPE(BDyn_InputType),           INTENT(IN   )  :: u           ! Inputs at t
      TYPE(BDyn_ParameterType),       INTENT(IN   )  :: p           ! Parameters
      TYPE(BDyn_ContinuousStateType), INTENT(IN   )  :: x           ! Continuous states at t
      TYPE(BDyn_DiscreteStateType),   INTENT(IN   )  :: xd          ! Discrete states at t
      TYPE(BDyn_ConstraintStateType), INTENT(IN   )  :: z           ! Constraint states at t (possibly a guess)
      TYPE(BDyn_OtherStateType),      INTENT(INOUT)  :: OtherState  ! Other/optimization states
      TYPE(BDyn_ConstraintStateType), INTENT(  OUT)  :: Z_residual  ! Residual of the constraint state equations using
                                                                      !     the input values described above
      INTEGER(IntKi),                   INTENT(  OUT)  :: ErrStat     ! Error status of the operation
      CHARACTER(*),                     INTENT(  OUT)  :: ErrMsg      ! Error message if ErrStat /= ErrID_None


      ! Initialize ErrStat

      ErrStat = ErrID_None
      ErrMsg  = "" 


      ! Solve for the constraint states here:

      Z_residual%DummyConstrState = 0

END SUBROUTINE BDyn_CalcConstrStateResidual
!----------------------------------------------------------------------------------------------------------------------------------
!----------------------------------------------------------------------------------------------------------------------------------
subroutine BDyn_gen_gll(N, x, w, ErrStat, ErrMsg)
!
! This subroutine determines the (N+1) Gauss-Lobatto-Legendre points x and weights w
!
! For details, see
! @book{Deville-etal:2002,
!  author =    {M. O. Deville and P. F. Fischer and E. H. Mund},
!  title =     {High-Order Methods for Incompressible Fluid Flow},
!  publisher = {Cambridge University Press},
!  address = {Cambridge},
!  year =      2002
!}
!
!..................................................................................................................................

   ! input variables

   INTEGER(IntKi),                 INTENT(IN   )  :: N           ! Order of spectral element
   REAL(ReKi),                     INTENT(  OUT)  :: x(N+1)      ! location of GLL nodes
   REAL(ReKi),                     INTENT(  OUT)  :: w(N+1)      ! quadrature weights at GLL nodes

   INTEGER(IntKi),                 INTENT(  OUT)  :: ErrStat     ! Error status of the operation
   CHARACTER(*),                   INTENT(  OUT)  :: ErrMsg      ! Error message if ErrStat /= ErrID_None

   ! local variables  

   REAL(ReKi)          :: tol       ! tolerance for newton-raphson solve
   INTEGER(IntKi)      :: maxit     ! maximum allowable iterations in newton-raphson solve
   REAL(ReKi)          :: x_it      ! current NR-iteration value
   REAL(ReKi)          :: x_old     ! last NR-iteration value

   REAL(ReKi)          :: dleg(N+1)   ! legendre polynomial

   INTEGER(IntKi)      :: N1        ! N+1

   INTEGER(IntKi)      :: i         ! do-loop counter
   INTEGER(IntKi)      :: j         ! do-loop counter
   INTEGER(IntKi)      :: k         ! do-loop counter

   ! Initialize ErrStat

   ErrStat = ErrID_None
   ErrMsg  = "" 

   tol = 1e-15

   N1 = N+1

   maxit = 1e3  

   ! enter known endpoints  [-1.0, 1.0]
   x(1) = -1.
   x(N1) = 1.

   pi = acos(-1.)  ! perhaps use NWTC library value, but does not matter here; just used to guess at solution

   do i = 1, N1

      x_it = -cos(pi * float(i-1) / N) ! initial guess - chebyshev points

      do j = 1, maxit
         x_old = x_it
         dleg(1) = 1.0
         dleg(2) = x_it
         do k = 2,N
            dleg(k+1) = (  (2.0*dfloat(k) - 1.0) * dleg(k) * x_it &
                            - (dfloat(k)-1.0)*dleg(k-1) ) / dfloat(k)
         enddo

         x_it = x_it - ( x_it * dleg(N1) - dleg(N) ) / &
                       (dfloat(N1) * dleg(N1) )

         if (abs(x_it - x_old) .lt. tol) then
            exit
         end if
      enddo

      if (i==maxit) then
         ErrStat = ErrID_Fatal
         ErrMsg  = ' Error in BeamDyn: BDyn_gen_gll: reached max iterations in gll solve'
      end if

      x(i) = x_it
      w(i) = 2.0 / (dfloat(N * N1) * dleg(N1)**2 )

   enddo

   return
end subroutine BDyn_gen_gll
!----------------------------------------------------------------------------------------------------------------------------------
subroutine BDyn_gen_deriv(N, xgll, deriv, ErrStat, ErrMsg)
!
! Calculates derivative array for order N one-dimensional basis function evaluated at location of (N+1) nodes
!
! deriv(i,j) = d phi_i(x) / d x |_{x_j}
!
! where phi_i(x) is the lagrangian interpolant associated with the ith node and x_j is the location of the jth node
!
! For details, see
! @book{Deville-etal:2002,
!  author =    {M. O. Deville and P. F. Fischer and E. H. Mund},
!  title =     {High-Order Methods for Incompressible Fluid Flow},
!  publisher = {Cambridge University Press},
!  address = {Cambridge},
!  year =      2002
!}
!
!..................................................................................................................................

   ! input variables

   INTEGER(IntKi),       INTENT(IN   )  :: N               ! Order of spectral element
   REAL(ReKi),           INTENT(IN   )  :: xgll(N+1)       ! location of GLL nodes
   REAL(ReKi),           INTENT(  OUT)  :: deriv(N+1,N+1)  ! derivative tensor

   INTEGER(IntKi),       INTENT(  OUT)  :: ErrStat         ! Error status of the operation
   CHARACTER(*),         INTENT(  OUT)  :: ErrMsg          ! Error message if ErrStat /= ErrID_None

   ! local variables  

   !REAL(ReKi)          :: tol       ! tolerance for newton-raphson solve
   !INTEGER(IntKi)      :: maxit     ! maximum allowable iterations in newton-raphson solve
   !REAL(ReKi)          :: x_it      ! current NR-iteration value
   !REAL(ReKi)          :: x_old     ! last NR-iteration value

   INTEGER(IntKi)      :: N1        ! N1 = N + 1

   INTEGER(IntKi)      :: i         ! do-loop counter
   INTEGER(IntKi)      :: j         ! do-loop counter
   INTEGER(IntKi)      :: k         ! do-loop counter

   REAL(ReKi) dleg(N+1,N+1)

   ! Initialize ErrStat

   ErrStat = ErrID_None
   ErrMsg  = "" 

   N1 = N+1

   do i = 1, N1
      dleg(1,i) = 1.0
      dleg(2,i) = xgll(i)
      do k = 2,N
         dleg(k+1,i) = ( (2.0*dfloat(k) - 1.0) * dleg(k,i) * xgll(i) &
                          - (dfloat(k)-1.0)*dleg(k-1,i) ) / dfloat(k)
      enddo
   enddo

   do i = 1, N1
      do j = 1, N1

         if (i.eq.j) then
            if (i.eq.1) then
               deriv(i,j) = -dfloat(N1*N)/4.0
            else if (i.eq.N1) then
               deriv(i,j) = +dfloat(N1*N)/4.0
            else
               deriv(i,j) = 0.0
            end if
         else

            deriv(i,j) = dleg(n1,j) / ( dleg(n1,i)*(xgll(j) - xgll(i)) )

         endif

      enddo
   enddo



   return
end subroutine BDyn_gen_deriv
!----------------------------------------------------------------------------------------------------------------------------------
!..................................................................................................................................
!++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
! WE ARE NOT YET IMPLEMENTING THE JACOBIANS...
!++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
END MODULE BeamDyn
!**********************************************************************************************************************************