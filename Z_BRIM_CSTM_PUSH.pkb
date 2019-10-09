/* Formatted on 6/28/2016 3:16:13 PM (QP5 v5.287) */
CREATE OR REPLACE PACKAGE BODY BANINST1.z_brim_cstm_push
AS
   /****************************************************************************
    REVISIONS:
    Ver    Date      Author          Description
    -----  --------  --------------  -------------------------------------------
    0.9.0  20150807  Marie Hicks     Created this package based on sample code
                                       found in Integrating Recruiter with Banner
                                       release 3.7.1 page 28
    1.0.0  20150810  Carl Ellsworth  Cleanup and revision for testing.
    1.0.1  20150811  Marie Hicks     Corrected a couple of the calls to the
                                       srtcstm_c cursor
    1.0.2  20150811  Marie Hicks     Corrected a call to the srtcstm_c
                                       cursor concerning highschoolgraddate
    1.0.3  20150813  Marie Hicks     Corrected custom field sequencing, added the
                                       fields needed to pull admission attributes
    1.0.4  20151116  Marie Hicks     Corrected custom field sequencing, altered
                                       concentration logic
    1.0.5  20160623  Marie Hicks     conversion of the concentration code removed,
                                       updated entity, and a couple column labels
    1.0.6  20160628  Marie Hicks     corrected 'contact' variable to
                                       'datatel_usuundergraduateapplication'
    1.1.0  20160628  Carl Ellsworth  added p_update_transfer_gpa
   ****************************************************************************/


   --p_update_transfer_gpa is a procedure requested by Joan Rudd in
   -- the School of Graduate Studies. They calculate a last 60 credit GPA,
   -- and input this to CRM Recruit. That value is not pushed to Banner.
   -- this function allows update to Banner intended to be called in batch.
   -- When CRM Recruit becomes more robust or USU processes change,
   -- BANINST1.GB_PCOL_DEGREE contains a more sophisticated table API
   PROCEDURE p_update_transfer_gpa (
      p_pidm               NUMBER,
      p_sbgi_code          VARCHAR2,
      p_gpa_transferred    NUMBER,
      p_degc_code          VARCHAR2 DEFAULT '000000')
   IS
   BEGIN
      UPDATE sordegr
         SET sordegr_gpa_transferred = p_gpa_transferred
       WHERE     sordegr_pidm = p_pidm
             AND sordegr_sbgi_code = p_sbgi_code
             AND sordegr_degc_code = p_degc_code;
   END p_update_transfer_gpa;


   --p_push is the main procedure provided by ellucian and updated by Marie to
   -- contain custom fields specific to USU processes.
   PROCEDURE p_push (p_ridm NUMBER)
   IS
      --
      lv_cstm_resd_desc     srtcstm.srtcstm_value%TYPE := NULL; --residency description from Recruiter
      lv_cstm_resd_code     srtprel.srtprel_resd_code%TYPE := NULL; -- residency description converted to code
      lv_cstm_dcsn_code     srtcstm.srtcstm_value%TYPE := NULL; --decision code from Recruiter
      lv_cstm_rnty_code     srtcstm.srtcstm_value%TYPE := NULL; --reentry attribute code from Recruiter
      lv_cstm_fgen_code     srtcstm.srtcstm_value%TYPE := NULL; --first generation attribute code from Recruiter
      lv_cstm_avet_code     srtcstm.srtcstm_value%TYPE := NULL; --Veteran attribute code from Recruiter
      lv_cstm_vben_code     srtcstm.srtcstm_value%TYPE := NULL; --Veteran benefits attribute code from Recruiter
      lv_cstm_lgcy_code     srtcstm.srtcstm_value%TYPE := NULL; --legacy code from Recruiter
      lv_cstm_grad_date     srtcstm.srtcstm_value%TYPE := NULL; --high school graduation date from Recruiter
      lv_cstm_scel_code     srtcstm.srtcstm_value%TYPE := NULL; --scholarship eligibility attribute from Recruiter
      lv_cstm_2bai_code     srtcstm.srtcstm_value%TYPE := NULL; --second bachelor aid attribute from Recruiter
      lv_cstm_site_code     srtcstm.srtcstm_value%TYPE := NULL; --site code from Recruiter
      lv_cstm_conc_code     stvmajr.stvmajr_code%TYPE := NULL; --concentration description converted to code

      lv_resd_code          srtprel.srtprel_resd_code%TYPE := NULL; --validated residency code
      lv_dcsn_code          srtprel.srtprel_apdc_code%TYPE := NULL; --validated decision code
      lv_rnty_code          saraatt.saraatt_atts_code%TYPE := NULL; --validated reentry code
      lv_fgen_code          saraatt.saraatt_atts_code%TYPE := NULL; --validated first generation code
      lv_avet_code          saraatt.saraatt_atts_code%TYPE := NULL; --validated veteran code
      lv_vben_code          saraatt.saraatt_atts_code%TYPE := NULL; --validated veteran benefits code
      lv_lgcy_code          spbpers.spbpers_lgcy_code%TYPE := NULL; --validated legacy code
      lv_grad_date          srthsch.srthsch_graduation_date%TYPE := NULL; --validated high school graduation date
      lv_scel_code          saraatt.saraatt_atts_code%TYPE := NULL; --validated scholarship eligibility code
      lv_2bai_code          saraatt.saraatt_atts_code%TYPE := NULL; --validated 2B aid eligibility code
      lv_site_code          srtprel.srtprel_site_code%TYPE := NULL; --validated site code
      lv_conc_code          srtprel.srtprel_majr_code%TYPE := NULL; --validated concentration code

      lv_pidm               srtiden.srtiden_pidm%TYPE := NULL; --matched pidm for accessing Banner tables
      lv_term_code          srtprel.srtprel_term_code%TYPE := NULL; --application term code
      lv_appl_id            srtprel.srtprel_appl_id%TYPE := NULL; --Recruiter application id
      lv_appl_no            saradap.saradap_appl_no%TYPE := NULL; --Banner application number
      lv_sbgi_code          srthsch.srthsch_sbgi_code%TYPE := NULL; --application high school code
      lv_dcsn_expt_cnt      PLS_INTEGER;                   --exception counter
      lv_user               srtprel.srtprel_user%TYPE := NULL; --custom record creator

      lv_curriculum_cnt     PLS_INTEGER;
      lv_curriculum_ref     sb_curriculum.curriculum_ref;
      lv_curriculum_rec     sb_curriculum.curriculum_rec;

      lv_fieldofstudy_cnt   PLS_INTEGER;
      lv_fieldofstudy_ref   sb_fieldofstudy.fieldofstudy_ref;
      lv_fieldofstudy_rec   sb_fieldofstudy.fieldofstudy_rec;

      lv_ccon_rule          sorccon.sorccon_ccon_rule%TYPE := NULL;
      lv_conc_attach_rule   sorlfos.sorlfos_conc_attach_rule%TYPE := NULL;
      lv_majr_code_attach   sorlfos.sorlfos_majr_code_attach%TYPE := NULL;

      lv_rowid_out          VARCHAR (18);
      lv_curr_error_out     NUMBER;
      lv_severity_out       VARCHAR2 (1) := NULL;
      lv_lfos_seqno_out     sorlfos.sorlfos_seqno%TYPE;

      -- custom field cursor

      CURSOR srtcstm_c (
         p_cstm_ridm         srtcstm.srtcstm_ridm%TYPE,
         p_cstm_entity       srtcstm.srtcstm_entity%TYPE,
         p_cstm_attribute    srtcstm.srtcstm_attribute%TYPE)
      IS
         SELECT srtcstm_value
           FROM srtcstm
          WHERE     srtcstm_ridm = p_cstm_ridm
                AND srtcstm_entity = p_cstm_entity
                AND srtcstm_attribute = p_cstm_attribute
                AND srtcstm_value IS NOT NULL;

      -- cursor iden/prel (tape load) data

      CURSOR srtiden_srtprel_c (p_cstm_ridm srtcstm.srtcstm_ridm%TYPE)
      IS
         SELECT srtiden_pidm,
                srtprel_term_code,
                srtprel_appl_id,
                srtprel_user
           FROM srtiden JOIN srtprel ON srtiden_ridm = srtprel_ridm
          WHERE srtiden_ridm = p_cstm_ridm AND srtiden_pidm IS NOT NULL; -- record is matched to banner

      -- cursor high school data

      CURSOR srthsch_c (p_cstm_ridm srtcstm.srtcstm_ridm%TYPE)
      IS
         SELECT srthsch_sbgi_code
           FROM srthsch
          WHERE srthsch_ridm = p_cstm_ridm AND srthsch_sbgi_code IS NOT NULL;


      -- cursor banner application

      CURSOR saradap_c (
         p_pidm         srtiden.srtiden_pidm%TYPE,
         p_term_code    srtprel.srtprel_term_code%TYPE,
         p_appl_id      srtprel.srtprel_appl_id%TYPE)
      IS
         SELECT saradap_appl_no
           FROM saradap
                JOIN srbraid
                   ON (    saradap_pidm = srbraid_pidm
                       AND saradap_term_code_entry = srbraid_term_code
                       AND saradap_appl_no = srbraid_appl_no)
          WHERE     saradap_pidm = p_pidm
                AND saradap_term_code_entry = p_term_code
                AND srbraid_recruiter_appl_id = p_appl_id;

      -- cursor concentration rule

      CURSOR sorccon_c (
         p_curr_rule              sorccon.sorccon_curr_rule%TYPE,
         p_majr_code_conc         sorccon.sorccon_majr_code_conc%TYPE,
         p_cmjr_rule              sorccon.sorccon_cmjr_rule%TYPE,
         p_lcur_term_code         sorccon.sorccon_term_code_eff%TYPE,
         p_lcur_term_code_ctlg    sorccon.sorccon_term_code_eff%TYPE,
         p_lfos_term_code_ctlg    sorccon.sorccon_term_code_eff%TYPE)
      IS
         SELECT sorccon_ccon_rule
           FROM sorccon bs
          WHERE     bs.sorccon_adm_ind = 'Y'
                AND bs.sorccon_curr_rule = p_curr_rule
                AND bs.sorccon_majr_code_conc = p_majr_code_conc
                AND NVL (bs.sorccon_cmjr_rule, 0) = NVL (p_cmjr_rule, 0)
                AND bs.sorccon_term_code_eff =
                       (SELECT MAX (m.sorccon_term_code_eff)
                          FROM sorccon m
                         WHERE     m.sorccon_curr_rule = bs.sorccon_curr_rule
                               AND NVL (m.sorccon_cmjr_rule, 0) =
                                      NVL (bs.sorccon_cmjr_rule, 0)
                               AND m.sorccon_majr_code_conc =
                                      bs.sorccon_majr_code_conc
                               AND m.sorccon_term_code_eff <=
                                      NVL (
                                         p_lfos_term_code_ctlg,
                                         NVL (p_lcur_term_code_ctlg,
                                              p_lcur_term_code)));
   BEGIN
      -- get tape load data
      OPEN srtiden_srtprel_c (p_ridm);

      FETCH srtiden_srtprel_c
         INTO lv_pidm,
              lv_term_code,
              lv_appl_id,
              lv_user;

      IF srtiden_srtprel_c%NOTFOUND
      THEN
         lv_pidm := NULL;
      END IF;

      CLOSE srtiden_srtprel_c;

      -- return if pidm not matched
      IF (lv_pidm IS NULL)
      THEN
         RETURN;
      END IF;

      -- get high school code
      OPEN srthsch_c (p_ridm);

      FETCH srthsch_c INTO lv_sbgi_code;

      IF srthsch_c%NOTFOUND
      THEN
         lv_sbgi_code := NULL;
      END IF;

      CLOSE srthsch_c;

      -- get custom values
      OPEN srtcstm_c (p_ridm, 'contact', 'new_usuresidency');

      FETCH srtcstm_c INTO lv_cstm_resd_desc;

      IF srtcstm_c%NOTFOUND
      THEN
         lv_cstm_resd_desc := NULL;
      END IF;

      CLOSE srtcstm_c;

      OPEN srtcstm_c (p_ridm, 'contact',                      --updated v1.0.1
                                        'new_proposeddecision');

      FETCH srtcstm_c INTO lv_cstm_dcsn_code;

      IF srtcstm_c%NOTFOUND
      THEN
         lv_cstm_dcsn_code := NULL;
      END IF;

      CLOSE srtcstm_c;

      OPEN srtcstm_c (p_ridm,
                      'datatel_usuundergraduateapplication',  --updated v1.0.6
                      'new_usureentrystudent');               --updated v1.0.5

      FETCH srtcstm_c INTO lv_cstm_rnty_code;

      IF srtcstm_c%NOTFOUND
      THEN
         lv_cstm_rnty_code := NULL;
      END IF;

      CLOSE srtcstm_c;

      OPEN srtcstm_c (p_ridm,
                      'datatel_usuundergraduateapplication',  --updated v1.0.6
                      'new_usufirstgenerationcollege');       --updated v1.0.5

      FETCH srtcstm_c INTO lv_cstm_fgen_code;

      IF srtcstm_c%NOTFOUND
      THEN
         lv_cstm_fgen_code := NULL;
      END IF;

      CLOSE srtcstm_c;

      OPEN srtcstm_c (p_ridm,
                      'datatel_usuundergraduateapplication',  --updated v1.0.6
                      'new_veteranorservicemember'            --updated v1.0.5
                                                  );

      FETCH srtcstm_c INTO lv_cstm_avet_code;

      IF srtcstm_c%NOTFOUND
      THEN
         lv_cstm_avet_code := NULL;
      END IF;

      CLOSE srtcstm_c;

      OPEN srtcstm_c (p_ridm,
                      'datatel_usuundergraduateapplication',  --updated v1.0.6
                      'new_benefitsveteran');                 --updated v1.0.5

      FETCH srtcstm_c INTO lv_cstm_vben_code;

      IF srtcstm_c%NOTFOUND
      THEN
         lv_cstm_vben_code := NULL;
      END IF;

      CLOSE srtcstm_c;

      OPEN srtcstm_c (p_ridm, 'contact', 'new_legacycodeforbanner');

      FETCH srtcstm_c INTO lv_cstm_lgcy_code;

      IF srtcstm_c%NOTFOUND
      THEN
         lv_cstm_lgcy_code := NULL;
      END IF;

      CLOSE srtcstm_c;

      OPEN srtcstm_c (p_ridm,
                      'datatel_usuundergraduateapplication',  --updated v1.0.5
                      'new_highschoolgraddate'                --updated v1.0.2
                                              );

      FETCH srtcstm_c INTO lv_cstm_grad_date;

      IF srtcstm_c%NOTFOUND
      THEN
         lv_cstm_grad_date := NULL;
      END IF;

      CLOSE srtcstm_c;

      OPEN srtcstm_c (p_ridm, 'contact',                      --UPDATED v1.0.4
                                        'new_scholarshipeligibility' --updated v1.0.3 (typo)
                                                                    );

      FETCH srtcstm_c INTO lv_cstm_scel_code;

      IF srtcstm_c%NOTFOUND
      THEN
         lv_cstm_scel_code := NULL;
      END IF;

      CLOSE srtcstm_c;

      OPEN srtcstm_c (p_ridm, 'contact',                      --updated v1.0.4
                                        'new_secondbachelorattribute' --updated v1.0.4
                                                                     );

      FETCH srtcstm_c INTO lv_cstm_2bai_code;

      IF srtcstm_c%NOTFOUND
      THEN
         lv_cstm_2bai_code := NULL;
      END IF;

      CLOSE srtcstm_c;

      OPEN srtcstm_c (p_ridm, 'contact', 'new_bannersitecodes');

      FETCH srtcstm_c INTO lv_cstm_site_code;

      IF srtcstm_c%NOTFOUND
      THEN
         lv_cstm_site_code := NULL;
      END IF;

      CLOSE srtcstm_c;

      OPEN srtcstm_c (p_ridm, 'contact',                      --updated v1.0.4
                                        'new_emphasisspecialization');

      FETCH srtcstm_c INTO lv_cstm_conc_code;                 --updated v1.0.5

      IF srtcstm_c%NOTFOUND
      THEN
         lv_cstm_conc_code := NULL;                           --updated v1.0.5
      END IF;

      CLOSE srtcstm_c;

      -- return if no values
      IF (    lv_cstm_resd_desc IS NULL
          AND lv_cstm_dcsn_code IS NULL
          AND lv_cstm_rnty_code IS NULL
          AND lv_cstm_fgen_code IS NULL
          AND lv_cstm_avet_code IS NULL
          AND lv_cstm_vben_code IS NULL
          AND lv_cstm_lgcy_code IS NULL
          AND lv_cstm_grad_date IS NULL
          AND lv_cstm_scel_code IS NULL
          AND lv_cstm_2bai_code IS NULL
          AND lv_cstm_site_code IS NULL
          AND lv_cstm_conc_code IS NULL)
      THEN
         RETURN;
      END IF;

      -- convert residency description to code
      IF (lv_cstm_resd_desc = 'Resident')
      THEN
         lv_cstm_resd_code := 'R';
      ELSIF (lv_cstm_resd_desc = 'Non-Resident')
      THEN
         lv_cstm_resd_code := 'N';
      ELSIF (lv_cstm_resd_desc = 'International Resident')
      THEN
         lv_cstm_resd_code := 'I';
      ELSIF (lv_cstm_resd_desc IS NOT NULL)
      THEN
         raise_application_error (-20001,
                                  g$_nls.get (
                                     'BRIM_CSTM_PUSH-0001',
                                     'SQL',
                                     'Invalid residency description, cannot convert: %01%',
                                     TO_CHAR (lv_cstm_resd_desc)));
      ELSE
         lv_cstm_resd_code := NULL;
      END IF;

      -- verify valid residency code
      IF (    lv_cstm_resd_code IS NOT NULL
          AND sb_stvresd.f_code_exists (TO_CHAR (lv_cstm_resd_code)) != 'Y')
      THEN
         raise_application_error (-20001,
                                  g$_nls.get ('BRIM_CSTM_PUSH-0002',
                                              'SQL',
                                              'Invalid residency code: %01%',
                                              TO_CHAR (lv_cstm_resd_code)));
      END IF;

      lv_resd_code := TO_CHAR (lv_cstm_resd_code);

      -- verify valid decision code
      IF (    lv_cstm_dcsn_code IS NOT NULL
          AND sb_stvapdc.f_code_exists (TO_CHAR (lv_cstm_dcsn_code)) != 'Y')
      THEN
         raise_application_error (-20001,
                                  g$_nls.get ('BRIM_CSTM_PUSH-0003',
                                              'SQL',
                                              'Invalid decision code: %01%',
                                              TO_CHAR (lv_cstm_dcsn_code)));
      END IF;

      lv_dcsn_code := TO_CHAR (lv_cstm_dcsn_code);

      --added v1.0.3
      --convert reentry value to attribute code
      IF (lv_cstm_rnty_code = 'True')
      THEN
         lv_cstm_rnty_code := 'RA5Y';
      ELSE
         lv_cstm_rnty_code := NULL;
      END IF;

      --verify valid reentry code
      IF (    lv_cstm_rnty_code IS NOT NULL
          AND sb_stvatts.f_code_exists (TO_CHAR (lv_cstm_rnty_code)) != 'Y')
      THEN
         raise_application_error (-20001,
                                  g$_nls.get ('BRIM_CSTM_PUSH-0004',
                                              'SQL',
                                              'Invalid re-entry code: %01%',
                                              TO_CHAR (lv_cstm_rnty_code)));
      END IF;

      lv_rnty_code := TO_CHAR (lv_cstm_rnty_code);

      --added v1.0.3
      --convert first generation value to attribute
      IF (lv_cstm_fgen_code = 'True')
      THEN
         lv_cstm_fgen_code := 'FGS';
      ELSE
         lv_cstm_fgen_code := NULL;
      END IF;


      --verify valid first generation code
      IF (    lv_cstm_fgen_code IS NOT NULL
          AND sb_stvatts.f_code_exists (TO_CHAR (lv_cstm_fgen_code)) != 'Y')
      THEN
         raise_application_error (-20001,
                                  g$_nls.get (
                                     'BRIM_CSTM_PUSH-0005',
                                     'SQL',
                                     'Invalid first generation code: %01%',
                                     TO_CHAR (lv_cstm_fgen_code)));
      END IF;

      lv_fgen_code := TO_CHAR (lv_cstm_fgen_code);

      --added v1.0.3
      --convert veteran value to attribute code
      IF (lv_cstm_avet_code = 'True')
      THEN
         lv_cstm_avet_code := 'AVET';
      ELSE
         lv_cstm_avet_code := NULL;
      END IF;

      -- verify valid veteran code
      IF (    lv_cstm_avet_code IS NOT NULL
          AND sb_stvatts.f_code_exists (TO_CHAR (lv_cstm_avet_code)) != 'Y')
      THEN
         raise_application_error (-20001,
                                  g$_nls.get ('BRIM_CSTM_PUSH-0006',
                                              'SQL',
                                              'Invalid veteran code: %01%',
                                              TO_CHAR (lv_cstm_avet_code)));
      END IF;

      lv_avet_code := TO_CHAR (lv_cstm_avet_code);

      --added v1.0.3
      --convert veteran benefits value to attribute code
      IF (lv_cstm_vben_code = 'True')
      THEN
         lv_cstm_vben_code := 'VDEP';
      ELSE
         lv_cstm_vben_code := NULL;
      END IF;

      --verify valid veteran benefits code
      IF (    lv_cstm_vben_code IS NOT NULL
          AND sb_stvatts.f_code_exists (TO_CHAR (lv_cstm_vben_code)) != 'Y')
      THEN
         raise_application_error (-20001,
                                  g$_nls.get (
                                     'BRIM_CSTM_PUSH_0007',
                                     'SQL',
                                     'Invalid veteran benefits code: %01%',
                                     TO_CHAR (lv_cstm_vben_code)));
      END IF;

      lv_vben_code := TO_CHAR (lv_cstm_vben_code);

      --verify valid legacy code
      IF (    lv_cstm_lgcy_code IS NOT NULL
          AND gb_stvlgcy.f_code_exists (TO_CHAR (lv_cstm_lgcy_code)) != 'Y')
      THEN
         raise_application_error (-20001,
                                  g$_nls.get ('BRIM_CSTM_PUSH_0008',
                                              'SQL',
                                              'Invalid legacy code: %01%',
                                              TO_CHAR (lv_cstm_lgcy_code)));
      END IF;

      lv_lgcy_code := TO_CHAR (lv_cstm_lgcy_code);

      --convert to valid graduation date
      IF (lv_cstm_grad_date IS NOT NULL)
      THEN
         lv_grad_date := TO_DATE (lv_cstm_grad_date, 'mm/dd/yyyy hh:mi:ss AM');
      END IF;


      --verify valid scholarship eligibility code
      IF (    lv_cstm_scel_code IS NOT NULL
          AND sb_stvatts.f_code_exists (TO_CHAR (lv_cstm_scel_code)) != 'Y')
      THEN
         raise_application_error (-20001,
                                  g$_nls.get (
                                     'BRIM_CSTM_PUSH_0009',
                                     'SQL',
                                     'Invalid scholarship eligibility code: %01%',
                                     TO_CHAR (lv_cstm_scel_code)));
      END IF;

      lv_scel_code := TO_CHAR (lv_cstm_scel_code);

      --verify valid second bachalor aid code
      IF (    lv_cstm_2bai_code IS NOT NULL
          AND sb_stvatts.f_code_exists (TO_CHAR (lv_cstm_2bai_code)) != 'Y')
      THEN
         raise_application_error (-20001,
                                  g$_nls.get (
                                     'BRIM_CSTM_PUSH_0010',
                                     'SQL',
                                     'Invalid second bachelors attribute code: %01%',
                                     TO_CHAR (lv_cstm_2bai_code)));
      END IF;

      lv_2bai_code := TO_CHAR (lv_cstm_2bai_code);

      --verify valid site code
      IF (    lv_cstm_site_code IS NOT NULL
          AND gb_stvsite.f_code_exists (TO_CHAR (lv_cstm_site_code)) != 'Y')
      THEN
         raise_application_error (-20001,
                                  g$_nls.get ('BRIM_CSTM_PUSH_0011',
                                              'SQL',
                                              'Invalid site code: %01%',
                                              TO_CHAR (lv_cstm_site_code)));
      END IF;

      lv_site_code := TO_CHAR (lv_cstm_site_code);


      --verify valid concentration code
      IF (    lv_cstm_conc_code IS NOT NULL
          AND gb_stvmajr.f_concentration_code_exists (
                 TO_CHAR (lv_cstm_conc_code)) != 'Y')
      THEN
         raise_application_error (-20001,
                                  g$_nls.get (
                                     'BRIM_CSTM_PUSH_0013',
                                     'SQL',
                                     'Invalid concentration code: %01%',
                                     TO_CHAR (lv_cstm_conc_code)));
      END IF;

      lv_conc_code := TO_CHAR (lv_cstm_conc_code);

      --get application number
      OPEN saradap_c (lv_pidm, lv_term_code, lv_appl_id);

      FETCH saradap_c INTO lv_appl_no;

      IF (saradap_c%NOTFOUND)
      THEN
         lv_appl_no := NULL;
      END IF;

      CLOSE saradap_c;

      -- return if no application was created
      IF (lv_appl_no IS NULL)
      THEN
         RETURN;
      END IF;

      -- initialize decision critical exceptions counter
      lv_dcsn_expt_cnt := 0;

      -- update legacy code
      IF (lv_lgcy_code IS NOT NULL)
      THEN
         BEGIN
            gb_bio.p_update (p_pidm => lv_pidm, p_lgcy_code => lv_lgcy_code);
         EXCEPTION
            WHEN OTHERS
            THEN
               raise_application_error (-20001,
                                        g$_nls.get (
                                           'BRIM_CSTM_PUST_0014',
                                           'SQL',
                                           'Error occurred attempting to update legacy code; %01%',
                                           SQLERRM));
               lv_dcsn_expt_cnt := lv_dcsn_expt_cnt + 1;
         END;
      END IF;

      -- update high school graduation date
      IF (lv_grad_date IS NOT NULL)
      THEN
         BEGIN
            sb_highschool.p_update (p_pidm              => lv_pidm,
                                    p_sbgi_code         => lv_sbgi_code,
                                    p_graduation_date   => lv_grad_date);
         EXCEPTION
            WHEN OTHERS
            THEN
               raise_application_error (-20001,
                                        g$_nls.get (
                                           'BRIM_CMST_PUSH_0015',
                                           'SQL',
                                           'Error occurred attempting to update high school record; %01%',
                                           SQLERRM));
               lv_dcsn_expt_cnt := lv_dcsn_expt_cnt + 1;
         END;
      END IF;

      -- update residency and site code
      IF (lv_resd_code IS NOT NULL AND lv_site_code IS NOT NULL)
      THEN
         BEGIN
            sb_admissionsapplication.p_update (
               p_pidm              => lv_pidm,
               p_term_code_entry   => lv_term_code,
               p_appl_no           => lv_appl_no,
               p_resd_code         => lv_resd_code,
               p_site_code         => lv_site_code);
         EXCEPTION
            WHEN OTHERS
            THEN
               raise_application_error (-20001,
                                        g$_nls.get (
                                           'BRIM_CSMT_PUSH_0016',
                                           'SQL',
                                           'Error occurred attempting to update admissions application; %01%',
                                           SQLERRM));
               lv_dcsn_expt_cnt := lv_dcsn_expt_cnt + 1;
         END;
      ELSE
         --ADDED 1.0.4
         lv_dcsn_expt_cnt := lv_dcsn_expt_cnt + 1;
      END IF;

      /* BEGIN Section added v1.0.3 */

      -- create re-entry attribute
      IF (lv_rnty_code IS NOT NULL)
      THEN
         BEGIN
            baninst1.z_stu_attributes.p_saraatt_insert (
               p_pidm        => lv_pidm,
               p_term_code   => lv_term_code,
               p_appl_no     => lv_appl_no,
               p_atts_code   => lv_rnty_code);
         EXCEPTION
            WHEN OTHERS
            THEN
               raise_application_error (-20001,
                                        g$_nls.get (
                                           'BRIM_CSTM_PUSH_0017',
                                           'SQL',
                                           'Error occurred attempting to create re-entry attribute; %01%',
                                           SQLERRM));
               lv_dcsn_expt_cnt := lv_dcsn_expt_cnt + 1;
         END;
      END IF;

      -- create first generation attribute
      IF (lv_fgen_code IS NOT NULL)
      THEN
         BEGIN
            baninst1.z_stu_attributes.p_saraatt_insert (
               p_pidm        => lv_pidm,
               p_term_code   => lv_term_code,
               p_appl_no     => lv_appl_no,
               p_atts_code   => lv_fgen_code);
         EXCEPTION
            WHEN OTHERS
            THEN
               raise_application_error (-20001,
                                        g$_nls.get (
                                           'BRIM_CSTM_PUSH_0018',
                                           'SQL',
                                           'Error occurred attempting to create first generation attribute; %01%',
                                           SQLERRM));
               lv_dcsn_expt_cnt := lv_dcsn_expt_cnt + 1;
         END;
      END IF;

      -- create veteran attribute
      IF (lv_avet_code IS NOT NULL)
      THEN
         BEGIN
            baninst1.z_stu_attributes.p_saraatt_insert (
               p_pidm        => lv_pidm,
               p_term_code   => lv_term_code,
               p_appl_no     => lv_appl_no,
               p_atts_code   => lv_avet_code);
         EXCEPTION
            WHEN OTHERS
            THEN
               raise_application_error (-20001,
                                        g$_nls.get (
                                           'BRIM_CSTM_PUSH_0019',
                                           'SQL',
                                           'Error occurred attempting to create veteran attribute; %01%',
                                           SQLERRM));
               lv_dcsn_expt_cnt := lv_dcsn_expt_cnt + 1;
         END;
      END IF;

      -- create veteran benefits attribute
      IF (lv_vben_code IS NOT NULL)
      THEN
         BEGIN
            baninst1.z_stu_attributes.p_saraatt_insert (
               p_pidm        => lv_pidm,
               p_term_code   => lv_term_code,
               p_appl_no     => lv_appl_no,
               p_atts_code   => lv_vben_code);
         EXCEPTION
            WHEN OTHERS
            THEN
               raise_application_error (-20001,
                                        g$_nls.get (
                                           'BRIM_CSTM_PUSH_0020',
                                           'SQL',
                                           'Error occurred attempting to create veteran benefits attribute; %01%',
                                           SQLERRM));
               lv_dcsn_expt_cnt := lv_dcsn_expt_cnt + 1;
         END;
      END IF;

      -- create scholarship eligibility attribute
      IF (lv_scel_code IS NOT NULL)
      THEN
         BEGIN
            baninst1.z_stu_attributes.p_saraatt_insert (
               p_pidm        => lv_pidm,
               p_term_code   => lv_term_code,
               p_appl_no     => lv_appl_no,
               p_atts_code   => lv_scel_code);
         EXCEPTION
            WHEN OTHERS
            THEN
               raise_application_error (-20001,
                                        g$_nls.get (
                                           'BRIM_CSTM_PUSH_0021',
                                           'SQL',
                                           'Error occurred attempting to create scholarship eligibility attribute; %01%',
                                           SQLERRM));
               lv_dcsn_expt_cnt := lv_dcsn_expt_cnt + 1;
         END;
      END IF;

      -- create second bachelor type attribute
      IF (lv_2bai_code IS NOT NULL)
      THEN
         BEGIN
            baninst1.z_stu_attributes.p_saraatt_insert (
               p_pidm        => lv_pidm,
               p_term_code   => lv_term_code,
               p_appl_no     => lv_appl_no,
               p_atts_code   => lv_2bai_code);
         EXCEPTION
            WHEN OTHERS
            THEN
               raise_application_error (-20001,
                                        g$_nls.get (
                                           'BRIM_CSTM_PUSH_0022',
                                           'SQL',
                                           'Error occurred attempting to create second bachelor type attribute; %01%',
                                           SQLERRM));
               lv_dcsn_expt_cnt := lv_dcsn_expt_cnt + 1;
         END;
      END IF;

      /* END SECTION added v1.0.3 */

      -- update the concentration code
      --
      IF (lv_conc_code IS NOT NULL)
      THEN
         --
         -- find the curriculum record that was inserted for this application
         --
         lv_curriculum_ref :=
            sb_curriculum.f_query_all (
               p_pidm        => lv_pidm,
               p_term_code   => lv_term_code,
               p_key_seqno   => lv_appl_no,
               p_lmod_code   => sb_curriculum_str.f_ADMISSIONS);
         lv_curriculum_cnt := 0;

         LOOP
            FETCH lv_curriculum_ref INTO lv_curriculum_rec;

            EXIT WHEN lv_curriculum_ref%NOTFOUND;
            lv_curriculum_cnt := lv_curriculum_cnt + 1;
         END LOOP;

         --
         -- issue match/push message if more than one curriculum record was found
         --
         IF (lv_curriculum_cnt > 1)
         THEN
            srkrcmp.p_insert_srtrcmp (p_ridm,
                                      'P',
                                      g$_nls.get (
                                         'BRIM_CSTM_PUSH-0023',
                                         'SQL',
                                         'Concentration code %01% not processed - found more than one curriculum record for the application',
                                         lv_conc_code));
            RETURN;
         END IF;

         --
         -- issue match/push message if the curriculum record was not found
         --
         IF (lv_curriculum_cnt = 0)
         THEN
            srkrcmp.p_insert_srtrcmp (p_ridm,
                                      'P',
                                      g$_nls.get (
                                         'BRIM_CSTM_PUSH-0024',
                                         'SQL',
                                         'Concentration code %01% not processed - curriculum record not found for the application',
                                         lv_conc_code));
            RETURN;
         END IF;

         --
         -- find the field of study record that was inserted for the curriculum
         --
         lv_fieldofstudy_ref :=
            sb_fieldofstudy.f_query_all (
               p_pidm         => lv_pidm,
               p_lcur_seqno   => lv_curriculum_rec.r_seqno);
         lv_fieldofstudy_cnt := 0;

         LOOP
            FETCH lv_fieldofstudy_ref INTO lv_fieldofstudy_rec;

            EXIT WHEN lv_fieldofstudy_ref%NOTFOUND;
            lv_fieldofstudy_cnt := lv_fieldofstudy_cnt + 1;
         END LOOP;

         --
         -- issue match/push message if more than one field of study record was found
         --
         IF (lv_fieldofstudy_cnt > 1)
         THEN
            srkrcmp.p_insert_srtrcmp (p_ridm,
                                      'P',
                                      g$_nls.get (
                                         'BRIM_CSTM_PUSH-0025',
                                         'SQL',
                                         'Concentration code %01% not processed - found more than one field of study record for the application',
                                         lv_conc_code));
            RETURN;
         END IF;

         --
         -- issue match/push message if the field of study record was not found
         --
         IF (lv_fieldofstudy_cnt = 0)
         THEN
            srkrcmp.p_insert_srtrcmp (p_ridm,
                                      'P',
                                      g$_nls.get (
                                         'BRIM_CSTM_PUSH-0026',
                                         'SQL',
                                         'Concentration code %01% not processed - field of study record not found for the application',
                                         lv_conc_code));
            RETURN;
         END IF;

         --
         -- get concentrations rule and then the attached major rule
         --
         IF (lv_fieldofstudy_rec.r_lfos_rule IS NOT NULL)
         THEN
            lv_conc_attach_rule := lv_fieldofstudy_rec.r_lfos_rule;
            lv_majr_code_attach := lv_fieldofstudy_rec.r_majr_code;

            OPEN sorccon_c (lv_curriculum_rec.r_curr_rule,
                            lv_conc_code,
                            lv_fieldofstudy_rec.r_lfos_rule,
                            lv_curriculum_rec.r_term_code,
                            lv_curriculum_rec.r_term_code_ctlg,
                            lv_fieldofstudy_rec.r_term_code_ctlg);

            FETCH sorccon_c INTO lv_ccon_rule;

            IF sorccon_c%NOTFOUND
            THEN
               CLOSE sorccon_c;

               --
               -- rule not found with attached major - check for base rule
               --
               lv_conc_attach_rule := NULL;
               lv_majr_code_attach := NULL;

               OPEN sorccon_c (lv_curriculum_rec.r_curr_rule,
                               lv_conc_code,
                               NULL,
                               lv_curriculum_rec.r_term_code,
                               lv_curriculum_rec.r_term_code_ctlg,
                               lv_fieldofstudy_rec.r_term_code_ctlg);

               FETCH sorccon_c INTO lv_ccon_rule;

               IF sorccon_c%NOTFOUND
               THEN
                  CLOSE sorccon_c;

                  srkrcmp.p_insert_srtrcmp (p_ridm,
                                            'P',
                                            g$_nls.get (
                                               'BRIM_CSTM_PUSH-0027',
                                               'SQL',
                                               'Concentration code %01% not processed - concentration not valid for curriculum rule',
                                               lv_conc_code));
                  RETURN;
               END IF;
            END IF;

            CLOSE sorccon_c;
         END IF;

         BEGIN
            sb_fieldofstudy.p_create (
               p_pidm                => lv_fieldofstudy_rec.r_pidm,
               p_lcur_seqno          => lv_fieldofstudy_rec.r_lcur_seqno,
               p_seqno               => NULL,
               p_lfst_code           => sb_fieldofstudy_str.f_CONCENTRATION,
               p_term_code           => lv_fieldofstudy_rec.r_term_code,
               p_priority_no         => lv_fieldofstudy_rec.r_priority_no,
               p_csts_code           => lv_fieldofstudy_rec.r_csts_code,
               p_cact_code           => lv_fieldofstudy_rec.r_cact_code,
               p_data_origin         => lv_fieldofstudy_rec.r_data_origin,
               p_user_id             => lv_fieldofstudy_rec.r_user_id,
               p_majr_code           => lv_conc_code,
               p_term_code_ctlg      => lv_fieldofstudy_rec.r_term_code_ctlg,
               p_term_code_end       => lv_fieldofstudy_rec.r_term_code_end,
               p_dept_code           => lv_fieldofstudy_rec.r_dept_code,
               p_lfos_rule           => lv_ccon_rule,
               p_conc_attach_rule    => lv_conc_attach_rule,
               p_start_date          => lv_fieldofstudy_rec.r_start_date,
               p_end_date            => lv_fieldofstudy_rec.r_end_date,
               p_tmst_code           => lv_fieldofstudy_rec.r_tmst_code,
               p_majr_code_attach    => lv_majr_code_attach,
               p_rolled_seqno        => NULL,
               p_override_severity   => 'N',
               p_rowid_out           => lv_rowid_out,
               p_curr_error_out      => lv_curr_error_out,
               p_severity_out        => lv_severity_out,
               p_lfos_seqno_out      => lv_lfos_seqno_out,
               p_user_id_update      => lv_fieldofstudy_rec.r_user_id_update,
               p_current_cde         => lv_fieldofstudy_rec.r_current_cde);
         EXCEPTION
            WHEN OTHERS
            THEN
               raise_application_error (-20001,
                                        g$_nls.get (
                                           'BRIM_CSTM_PUSH-0028',
                                           'SQL',
                                           'Error occurred attempting to add field of study record for concentration; %01%',
                                           SQLERRM));
               lv_dcsn_expt_cnt := lv_dcsn_expt_cnt + 1;
         END;
      END IF;

      -- Create application decision
      IF (lv_dcsn_code IS NOT NULL AND lv_dcsn_expt_cnt = 0)
      THEN
         DECLARE
            lv_seq_no   sarappd.sarappd_seq_no%TYPE := 0; -- passing zero will cause the procedure to generate a new decision sequence number for the record; reference sb_applicaton_decision body line 301
            lv_rowid    gb_common.internal_record_id_type := NULL;
         BEGIN
            sb_application_decision.p_create (
               p_pidm              => lv_pidm,
               p_term_code_entry   => lv_term_code,
               p_appl_no           => lv_appl_no,
               p_seq_no_inout      => lv_seq_no, -- passing zero will cause the procedure to generate a new decision sequence number for the record; reference sb_applicaton_decision body line 301
               p_apdc_code         => lv_dcsn_code,
               p_maint_ind         => 'U', -- passing U indicates the records was maintained by the 'BRIM' user
               p_user              => lv_user,
               p_rowid_out         => lv_rowid);
         EXCEPTION
            WHEN OTHERS
            THEN
               raise_application_error (-20001,
                                        g$_nls.get (
                                           'BRIM_CSTM_PUSH-0029',
                                           'SQL',
                                           'Error occurred attempting to create application decision record: %01%',
                                           SQLERRM));
         END;
      END IF;
   END p_push;
END z_brim_cstm_push;
/
