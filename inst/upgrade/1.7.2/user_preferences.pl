#!/usr/bin/perl -w

use strict;
use File::Spec::Functions qw(catdir updir);
use FindBin;
use lib catdir $FindBin::Bin, updir, 'lib';
use bric_upgrade qw(:all);
use Bric::Config qw(:char);

do_sql q/
INSERT INTO class (id, key_name, pkg_name, disp_name, plural_name, description, distributor)
VALUES (78, 'user_pref', 'Bric::Util::UserPref', 'User Preference', 'User Preferences', 'User preferences', 0)
/;

do_sql q/
INSERT INTO event_type (id, key_name, name, description, class__id, active)
VALUES (NEXTVAL('seq_event_type'), 'user_pref_save', 'User Preference Changes Saved', 'User preference profile changes were saved.', 78, 1)
/;

do_sql q/
INSERT INTO event_type (id, key_name, name, description, class__id, active)
VALUES (NEXTVAL('seq_event_type'), 'user_pref_reset', 'User Preference Reset', 'User preference was reset to default.', 78, 1)
/;

do_sql q/CREATE SEQUENCE seq_usr_pref START 1024/;

do_sql q/CREATE TABLE usr_pref (
         id           NUMERIC(10, 0)  NOT NULL
                                      DEFAULT NEXTVAL('seq_usr_pref'),
         pref__id     NUMERIC(10, 0)  NOT NULL,
         usr__id      NUMERIC(10, 0)  NOT NULL,
         value        VARCHAR(256)    NOT NULL,
         CONSTRAINT pk_usr_pref__pref__id__value PRIMARY KEY (id)
         )/;

do_sql q/ALTER TABLE pref ADD COLUMN
         can_be_overridden  NUMERIC(1,0)   NOT NULL DEFAULT 0,
                                           CONSTRAINT ck_pref__can_be_overridden
                                             CHECK (can_be_overridden IN (0,1))q/;

do_sql q/CREATE UNIQUE INDEX udx_usr_pref__pref__id__usr__id ON usr_pref(pref__id, usr__id)/;

do_sql q/CREATE INDEX idx_usr_pref__usr__id ON usr_pref(usr__id)/;

do_sql q/
ALTER TABLE    usr_pref
ADD CONSTRAINT fk_pref__usr_pref FOREIGN KEY (pref__id)
REFERENCES     pref(id) ON DELETE CASCADE
/;

do_sql
ALTER TABLE    usr_pref
ADD CONSTRAINT fk_usr__usr_pref FOREIGN KEY (usr__id)
REFERENCES     usr(id) ON DELETE CASCADE
/;


my $char_set = CHAR_SET;

do_sql qq/
INSERT INTO pref (id, name, description, value, def, manual, opt_type)
VALUES (14, 'Character Set',
        'The default character set to use for display.',
        '$char_set', 'UTF-8', 0, 'select')
/;

do_sql q/
INSERT INTO member (id, grp__id, class__id, active)
VALUES (900, 22, 48, 1)
/;

do_sql q/
INSERT INTO pref_member (id, object_id, member__id
VALUES (14, 14, 900)
/;

-- These values were hand-picked from Encode::Supported

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'UTF-8', 'UTF-8')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'iso-8859-1', 'ISO-8859-1')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'iso-8859-2', 'ISO-8859-2')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'iso-8859-3', 'ISO-8859-3')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'iso-8859-4', 'ISO-8859-4')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'iso-8859-5', 'ISO-8859-5')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'iso-8859-6', 'ISO-8859-6')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'iso-8859-7', 'ISO-8859-7')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'iso-8859-8', 'ISO-8859-8')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'iso-8859-9', 'ISO-8859-9')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'iso-8859-10', 'ISO-8859-10')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'iso-8859-11', 'ISO-8859-11')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'iso-8859-13', 'ISO-8859-13')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'iso-8859-14', 'ISO-8859-14')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'iso-8859-15', 'ISO-8859-15')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'iso-8859-16', 'ISO-8859-16')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'viscii', 'Viscii (Vietnamese)')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'gb-2312', 'GB-2312')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'Big5', 'Big5')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'euc-jp', 'EUC-JP')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'shiftjis', 'ShiftJIS')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'iso-2022-jp', 'ISO-2022-JP')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'euc-kr', 'EUC-KR')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'iso-2022-kr', 'ISO-2022-KR')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'koi8-r', 'KOI8-R')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (14, 'koi8-u', 'KOI8-U')
/;


my $lang = lc LANGUAGE;

do_sql qq/
INSERT INTO pref (id, name, description, value, def, manual, opt_type)
VALUES (15, 'Language',
        'The default language to use for display.',
        '$lang', 'en_us', 0, 'select')
/;

do_sql q/
INSERT INTO member (id, grp__id, class__id, active)
VALUES (901, 22, 48, 1)
/;

do_sql q/
INSERT INTO pref_member (id, object_id, member__id)
VALUES (15, 15, 901)
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (15, 'en_us', 'en_us')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (15, 'de_de', 'de_de')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (15, 'it_it', 'it_it')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (15, 'pt_pt', 'pt_pt')
/;

do_sql q/
INSERT INTO pref_opt (pref__id, value, description)
VALUES (15, 'zh_tw', 'zh_tw')
/;


do_sql q/UPDATE pref