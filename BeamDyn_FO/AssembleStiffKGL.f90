   SUBROUTINE AssembleStiffKGL(nelem,node_elem,dof_elem,dof_node,ElemK,GlobalK)

   REAL(ReKi),INTENT(IN)::ElemK(:,:)
   INTEGER(IntKi),INTENT(IN)::nelem,node_elem,dof_elem,dof_node
   REAL(ReKi),INTENT(INOUT)::GlobalK(:,:)

   INTEGER(IntKi)::i,j,temp_id1,temp_id2

   DO i=1,dof_elem
       temp_id1 = (nelem-1)*(node_elem-1)*dof_node+i
       DO j=1,dof_elem
           temp_id2 = (nelem-1)*(node_elem-1)*dof_node+j
           GlobalK(temp_id1,temp_id2) = GlobalK(temp_id1,temp_id2) + ElemK(i,j)
       ENDDO
   ENDDO

   END SUBROUTINE AssembleStiffKGL