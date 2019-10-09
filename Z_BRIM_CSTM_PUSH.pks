/* Formatted on 8/10/2015 12:36:47 PM (QP5 v5.269.14213.34746) */
CREATE OR REPLACE PACKAGE baninst1.z_brim_cstm_push
AS
   /****************************************************************************
      NAME:     z_brim_cstm_push
      PURPOSE:  This package is used to validate and store custom fields that
                   are being sent to Banner from Recruiter.
   ****************************************************************************/
   PROCEDURE p_push (p_ridm NUMBER);
END z_brim_cstm_push;
