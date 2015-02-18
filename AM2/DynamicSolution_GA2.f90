   SUBROUTINE DynamicSolution_GA2( uuN0,uuNf,vvNf,aaNf,xxNf,               &
                                   Stif0,Mass0,gravity,u,damp_flag,beta,   &
                                   node_elem,dof_node,elem_total,dof_total,&
                                   node_total,niter,ngp,coef)

   REAL(ReKi),         INTENT(IN   ):: uuN0(:)
   REAL(ReKi),         INTENT(IN   ):: Stif0(:,:,:)
   REAL(ReKi),         INTENT(IN   ):: Mass0(:,:,:)
   REAL(ReKi),         INTENT(IN   ):: gravity(:)
   TYPE(BD_InputType), INTENT(IN   ):: u
   REAL(ReKi),         INTENT(IN   ):: beta(:)
   REAL(DbKi),         INTENT(IN   ):: coef(:)
   INTEGER(IntKi),     INTENT(IN   ):: damp_flag
   INTEGER(IntKi),     INTENT(IN   ):: node_elem
   INTEGER(IntKi),     INTENT(IN   ):: dof_node
   INTEGER(IntKi),     INTENT(IN   ):: elem_total
   INTEGER(IntKi),     INTENT(IN   ):: dof_total
   INTEGER(IntKi),     INTENT(IN   ):: node_total
   INTEGER(IntKi),     INTENT(IN   ):: ngp
   INTEGER(IntKi),     INTENT(IN   ):: niter
   REAL(ReKi),         INTENT(INOUT):: uuNf(:)
   REAL(ReKi),         INTENT(INOUT):: vvNf(:)
   REAL(ReKi),         INTENT(INOUT):: aaNf(:)
   REAL(ReKi),         INTENT(INOUT):: xxNf(:)
 
   REAL(ReKi):: errf,temp1,temp2,errx
   REAL(ReKi):: StifK(dof_total,dof_total), RHS(dof_total)
   REAL(ReKi):: MassM(dof_total,dof_total), DampG(dof_total,dof_total)
   
   REAL(ReKi)                      :: F_PointLoad(dof_total)

   REAL(ReKi):: StifK_LU(dof_total-6,dof_total-6),RHS_LU(dof_total-6)

   REAL(ReKi):: F_ext(dof_total)
   REAL(ReKi):: Fedge(dof_total)

   REAL(ReKi)::ai(dof_total),ai_temp(dof_total-6)
   REAL(ReKi)::feqv(dof_total-6),Eref,Enorm
   REAL(ReKi),PARAMETER:: TOLF = 1.0D-10   
   
   REAL(ReKi)::d
   INTEGER(IntKi):: indx(dof_total-6)

   INTEGER(IntKi)::i,j,k
   
   Fedge = 0.0D0

   ai = 0.0D0
   Eref = 0.0D0

   DO i=1,niter
!       WRITE(*,*) "N-R Iteration #", i
!       IF(i==10) STOP
       StifK = 0.0D0
       RHS = 0.0D0
       MassM = 0.0D0
       DampG = 0.0D0

       CALL BldGenerateDynamicElement(uuN0,uuNf,vvNf,aaNf,                 &
                                      Stif0,Mass0,gravity,u,damp_flag,beta,&
                                      elem_total,node_elem,dof_node,ngp,   &
                                      StifK,RHS,MassM,DampG)
       StifK = MassM + coef(7) * DampG + coef(8) * StifK
       DO j=1,node_total
           temp_id = (j-1)*dof_node
           F_PointLoad(temp_id+1:temp_id+3) = u%PointLoad%Force(1:3,j)
           F_PointLoad(temp_id+4:temp_id+6) = u%PointLoad%Moment(1:3,j)
       ENDDO
       RHS(:) = RHS(:) + F_PointLoad(:)
!       k=0
!       DO j=1,dof_total
!           WRITE(*,*) "j=",j
!           WRITE(*,*) "RHS(j)=",RHS(j)
!           WRITE(*,*) StifK(j,1+k),StifK(j,2+k),StifK(j,3+k),StifK(j,4+k),StifK(j,5+k),StifK(j,6+k)
!       ENDDO
!       STOP
       errf = 0.0D0
       feqv = 0.0D0
       DO j=1,dof_total-6
           feqv(j) = RHS(j+6)
           RHS_LU(j) = RHS(j+6)
           DO k=1,dof_total-6
               StifK_LU(j,k) = StifK(j+6,k+6)
           ENDDO
       ENDDO
!       CALL Norm(dof_total-6,feqv,errf)
!       WRITE(*,*) "NORM(feqv) = ", errf
       
!       CALL CGSolver(RHS,StifK,ai,bc,dof_total)
       CALL ludcmp(StifK_LU,dof_total-6,indx,d)
       CALL lubksb(StifK_LU,dof_total-6,indx,RHS_LU,ai_temp)

       ai = 0.0D0
       DO j=1,dof_total-6
           ai(j+6) = ai_temp(j)
       ENDDO
       IF(i==1) Eref = SQRT(DOT_PRODUCT(ai_temp,feqv))*TOLF
       IF(i .GT. 1) THEN
           Enorm = 0.0D0
           Enorm = SQRT(DOT_PRODUCT(ai_temp,feqv))
!           WRITE(*,*) "Enorm = ", Enorm
!           WRITE(*,*) "Eref = ", Eref
           IF(Enorm .LE. Eref) RETURN
       ENDIF    
       CALL UpdateDynamic(ai,uuNf,vvNf,aaNf,xxNf,coef,node_total,dof_node)
           
!       DO j=dof_total-5,dof_total
!           WRITE(*,*) "j=",j
!           WRITE(*,*) "uuNf(j)=",uuNf(j)
!       ENDDO
!       STOP
       IF(i==niter) THEN
           WRITE(*,*) "Solution does not converge after the maximum number of iterations"
           STOP
       ENDIF
   ENDDO
   
   END SUBROUTINE DynamicSolution_GA2