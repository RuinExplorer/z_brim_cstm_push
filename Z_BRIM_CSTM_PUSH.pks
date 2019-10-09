CREATE OR REPLACE PACKAGE BANINST1.z_brim_cstm_push
AS
   /****************************************************************************
      NAME:     z_brim_cstm_push
      PURPOSE:  This package is used to validate and store custom fields that
                   are being sent to Banner from Recruiter.
   ****************************************************************************/
   PROCEDURE p_update_transfer_gpa (
      p_pidm               NUMBER,
      p_sbgi_code          VARCHAR2,
      p_gpa_transferred    NUMBER,
      p_degc_code          VARCHAR2 DEFAULT '000000');

   PROCEDURE p_push (p_ridm NUMBER);
END z_brim_cstm_push;
/
