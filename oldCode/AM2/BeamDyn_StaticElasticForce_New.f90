   SUBROUTINE BeamDyn_StaticElasticForce_New(E1,RR0,kapa,Stif,cet,uuu,Fc,Fd,Oe,Pe,Qe,Se)

   REAL(ReKi),INTENT(IN   ):: E1(:)
   REAL(ReKi),INTENT(IN   ):: RR0(:,:)
   REAL(ReKi),INTENT(IN   ):: kapa(:)
   REAL(ReKi),INTENT(IN   ):: Stif(:,:)
   REAL(ReKi),INTENT(IN   ):: uuu(:)
   REAL(ReKi),INTENT(IN   ):: cet
   REAL(ReKi),INTENT(  OUT):: Fc(:)
   REAL(ReKi),INTENT(  OUT):: Fd(:)    
   REAL(ReKi),INTENT(  OUT):: Oe(:,:)
   REAL(ReKi),INTENT(  OUT):: Pe(:,:)
   REAL(ReKi),INTENT(  OUT):: Qe(:,:) 
   REAL(ReKi),INTENT(  OUT):: Se(:,:) 
 
   REAL(ReKi)              :: eee(6)
   REAL(ReKi)              :: fff(6)
   REAL(ReKi)              :: tempS(3)
   REAL(ReKi)              :: tempK(3)
   REAL(ReKi)              :: Wrk(3)
   REAL(ReKi)              :: e1s
   REAL(ReKi)              :: k1s
   REAL(ReKi)              :: Wrk33(3,3)
   REAL(ReKi)              :: C11(3,3)
   REAL(ReKi)              :: C12(3,3)
   REAL(ReKi)              :: C21(3,3)
   REAL(ReKi)              :: C22(3,3)
   REAL(ReKi)              :: epsi(3,3)
   REAL(ReKi)              :: mu(3,3)
   REAL(ReKi)              :: temp_H(3,3)
   REAL(ReKi)              :: temp_Hinv(3,3)
   REAL(ReKi)              :: temp_pp(3)
   REAL(ReKi)              :: temp_Hp(3,3)
   REAL(ReKi)              :: temp_B(3,3)
   REAL(ReKi)              :: temp_GAMA(6,6)
   INTEGER(IntKi)          :: i
   INTEGER(IntKi)          :: j

   eee(:) = 0.0D0 
   DO i=1,3
       eee(i) = E1(i) - RR0(i,1)
       eee(i+3) = kapa(i)

       tempS(i) = eee(i)
       tempK(i) = eee(i+3)
   ENDDO
   fff(:) = 0.0D0 
   fff(:) = MATMUL(Stif,eee)

   Wrk(:) = 0.0D0     
   Wrk(:) = MATMUL(TRANSPOSE(RR0),tempS)
   e1s = Wrk(1)      !epsilon_{11} in material basis

   Wrk(:) = 0.0D0
   Wrk(:) = MATMUL(TRANSPOSE(RR0),tempK)
   k1s = Wrk(1)      !kapa_{1} in material basis
     
   DO i=1,3
       fff(i)   = fff(i) + 0.5D0*cet*k1s*k1s*RR0(i,1)
       fff(i+3) = fff(i+3) + cet*e1s*k1s*RR0(i,1)
   ENDDO 

   Fc(:) = 0.0D0
   Fc(:) = fff(:)
   Wrk(:) = 0.0D0 
   Wrk(1:3) = fff(1:3)
   Fd(:) = 0.0D0 
   Fd(4:6) = MATMUL(TRANSPOSE(Tilde(E1)),Wrk)

   C11(:,:) = 0.0D0
   C12(:,:) = 0.0D0
   C21(:,:) = 0.0D0
   C22(:,:) = 0.0D0
   C11(1:3,1:3) = Stif(1:3,1:3)
   C12(1:3,1:3) = Stif(1:3,4:6)
   C21(1:3,1:3) = Stif(4:6,1:3)
   C22(1:3,1:3) = Stif(4:6,4:6)

   Wrk(:) = 0.0D0
   DO i=1,3
       Wrk(i) = RR0(i,1)
   ENDDO
   Wrk33(:,:) = 0.0D0
   Wrk33(:,:) = OuterProduct(Wrk,Wrk) 
   C12(:,:) = C12(:,:) + cet*k1s*Wrk33(:,:) 
   C21(:,:) = C21(:,:) + cet*k1s*Wrk33(:,:)
   C22(:,:) = C22(:,:) + cet*e1s*Wrk33(:,:)

   epsi(:,:) = 0.0D0 
   mu(:,:) = 0.0D0
   epsi(:,:) = MATMUL(C11,Tilde(E1))
   mu(:,:) = MATMUL(C21,Tilde(E1))
   
   Wrk(:) = 0.0D0

   Oe(:,:) = 0.0D0
   CALL CrvMatrixH(uuu(4:6),temp_H)
   CALL CrvMatrixHinv(uuu(4:6),temp_Hinv)
   temp_pp(:) = MATMUL(temp_Hinv,kapa)
   CALL CrvMatrixB(uuu(4:6),temp_pp,temp_B)
   temp_Hp(:,:) = temp_B + MATMUL(Tilde(kapa),temp_H)
   Oe(1:3,4:6) = MATMUL(Tilde(E1),temp_H)
   Oe(4:6,4:6) = temp_Hp(:,:)
   Oe(:,:) = MATMUL(Stif,Oe)
   
   Wrk(1:3) = fff(1:3)
   Oe(1:3,4:6) = Oe(1:3,4:6) - MATMUL(Tilde(Wrk),temp_H)
   Wrk(:) = 0.0D0
   Wrk(1:3) = fff(4:6)
   Oe(4:6,4:6) = Oe(4:6,4:6) - MATMUL(Tilde(Wrk),temp_H)
   
   Se(:,:) = 0.0D0
   DO i=1,3
       Se(i,i) = 1.0D0
   ENDDO
   Se(4:6,4:6) = temp_H(:,:)
   Se(:,:) = MATMUL(Stif,Se)

   Pe(:,:) = 0.0D0
   Wrk(:) = 0.0D0
   Wrk(1:3) = fff(1:3)
   temp_GAMA(:,:) = 0.0D0
   temp_GAMA(4:6,1:3) = TRANSPOSE(Tilde(E1))
   Pe(4:6,1:3) = Tilde(Wrk)
   Pe(:,:) = Pe(:,:) + MATMUL(temp_GAMA,Se)

   Qe(:,:) = 0.0D0
   Qe(:,:) = MATMUL(temp_GAMA,Oe)

   END SUBROUTINE BeamDyn_StaticElasticForce_New