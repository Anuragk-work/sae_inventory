<?
//=============================================================================
//
//	FILE:			SubtotalGLResolveManager.cls
//	AUTHOR:			MJagadish
//	DESCRIPTION:	A manager class for the SUBTOTALGLRESOLVE entity
//
//
//	(C)2000, Intacct Corporation, All Rights Reserved
//
//	Intacct Corporation Proprietary Information.
//	This document contains trade secret data that belongs to Intacct 
//	corporation and is protected by the copyright laws. Information herein 
//	may not be used, copied or disclosed in whole or part without prior 
//	written consent from Intacct Corporation.
//
//=============================================================================

import('EntityManager');

/**
 * Class SubtotalGLResolveManager
 *
 * NOTE:    DANGER!! Even though this IS an Entity Manager, and even though there IS a .ent file,
 *                  there is no RECROD NUMBER, and the given vid of SUBTOTKEY is not enough.  You
 *                  need a compound key and EntityManager doesn't handle that well at the moment.
 *                  Thus, we don't rely on the standard queries.....
 */
class SubtotalGLResolveManager extends EntityManager
{
    /**
     * @param array $params
     */
    function __construct($params = array())
    {
        parent::__construct($params);
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values) 
    {

        return ExecStmt(
            array("INSERT INTO deglsubtotresolve ".
            "(dochdrkey,subtotkey,glentrykey,amount,currency,trx_amount,orig_trtype,cny#) VALUES ".
            "(:1,:2,:3,:4,:5,:6,:7,:8)", 
            $values['DOCHDRKEY'], $values['SUBTOTKEY'], $values['GLENTRYKEY'],
            $values['AMOUNT'], $values['CURRENCY'],
            $values['TRX_AMOUNT'], $values['ORIG_TRTYPE'], $values['CNY#'])
        );
    }




    /**
     *  If we are adding resolves, just go ahead and add them.  Otherwise, if we are upserting
     * the document, upsert the deglresolves by reading existing deglresolves, matching
     * as best we can, and adding/setting them.  Delete any remaining deglresolves.
     *
     * Note: on advice from Senthil, made this 'static'
     *
     * @param array         $glResolves           array of deglresolves we want, by docentrykey
     *
     * @return bool                                 did it work?
     *
     */
    static function addOrUpsert($glResolves)
    {
        DocumentManager::updatingEntity('subtotalglresolve');
        $ok = true;

        if (!empty($glResolves)) {
            $subtotalResolveMgr = Globals::$g->gManagerFactory->getManager('subtotalglresolve');
            DocumentManager::updatingEntity($subtotalResolveMgr->_entity);
            $matchmaker = new Matchmaker($subtotalResolveMgr, Matchmaker::ALLOW_IGNORE, Matchmaker::DELETE_BY_RECORDNO, [], [], false );

            // if upsert is in progress, look for existing records, otherwise don't
            $ok = $ok && $matchmaker->upsert($glResolves, (DocumentManager::$upsertFeaturInUse ? 'DOCHDRKEY' : ''), $glResolves[0]['DOCHDRKEY']);
        }
        return $ok;
    }






    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularSet(&$values) 
    {
        // somewhere, someone was using this clunky set, so we continue to support it....
        if (isset($values['NEW_GLENTRYKEY']) && isset($values['OLD_GLENTRYKEY'])) {
            return ExecStmt(
                array("UPDATE deglsubtotresolve set glentrykey=:1 where cny#=:2 and glentrykey=:3",
                    $values['NEW_GLENTRYKEY'], $values['CNY#'], $values['OLD_GLENTRYKEY'])
            );
        } else {
            // the key is really subtotkey and orig_trtype; someday we should add a record#!!
            return ExecStmt(
                array("UPDATE deglsubtotresolve set 
                    glentrykey=:1, amount=:2, currency=:3, trx_amount=:4 
                    where cny#=:5 and dochdrkey=:6 and subtotkey=:7 and orig_trtype=:8",
                    $values['GLENTRYKEY'], $values['AMOUNT'], $values['CURRENCY'],
                    $values['TRX_AMOUNT'], $values['CNY#'], $values['DOCHDRKEY'],
                    $values['SUBTOTKEY'], $values['ORIG_TRTYPE']
                )
            );
        }

    }

    /**
     *  Get()
     *      NOTE: DANGER!! This is really "get a bunch of related fields for the parent docheader" and not
     *          a regular Entity-Manager get()!!!!!  (Delete() is broken in this way too)
     *
     *  So, you CANNOT use this class with normal CRUD operations.
     *
     * @param string    $dochdrkey
     * @param string[]|null $fields
     *
     * @return bool|array
     */
    function Get($dochdrkey, $fields = null)
    {
        // GET DIMENSION KEYS
        $dimensionKeys = IADimensions::GetDimensionKeys();
        if ( isset($dimensionKeys) && count($dimensionKeys) > 0 ) {
            // we need to prepend the glentry table name to the dim keys
            $dimKeys = array();
            foreach ( $dimensionKeys as $dimid ) {
                $dimKeys[] = 'glentry.' . $dimid; 
            }
            $glentryDimensionFieldStr = join(', ', $dimKeys);
            $glentryDimensionFieldStr = ( $glentryDimensionFieldStr ? $glentryDimensionFieldStr . ',' : '' );
        }

        if ( !util_isPlatformDisabled() && IADimensions::isCustomDimensionsEnabled() ) {
            /** @noinspection PhpUndefinedVariableInspection */
            $glentryDimensionFieldStr .= 'glentry.customdimensions, ';
        }

        /** @noinspection PhpUndefinedVariableInspection */
        $qry = "SELECT   glentry.record#, glentry.status, glentry.entry_date, glentry.batch#,
						 glentry.document, glentry.description, glaccount.acct_no glaccountkey,
						 glentry.basecurr, glentry.currency, glentry.user#,
						 deglsubtotresolve.amount, deglsubtotresolve.trx_amount, LOCATION.location_no location#,
						 department.dept_no dept#, glentry.line_no, glentry.tr_type dr_cr,
						 glentry.exch_rate_date, glentry.exch_rate_type_id,
						 glentry.exchange_rate, $glentryDimensionFieldStr 
						 glentry.recon_date, deglsubtotresolve.orig_trtype, 
                         deglsubtotresolve.subtotkey as subtotalkey, deglsubtotresolve.dochdrkey as dochdrno
					FROM glentry, glaccount, deglsubtotresolve, department, LOCATION
				   WHERE deglsubtotresolve.dochdrkey = :1
					 AND glentry.record# = deglsubtotresolve.glentrykey
					 AND deglsubtotresolve.cny#(+) = :2
					 AND glentry.account# = glaccount.record#(+)
					 AND glaccount.cny#(+) = :2
					 AND glentry.dept# = department.record#(+)
					 AND department.cny#(+) = :2
					 AND glentry.location# = LOCATION.record#(+)
					 AND LOCATION.cny#(+) = :2
					 AND glentry.cny#(+) = :2
				ORDER BY glentry.line_no";

        /*$qry = "select * from deglresolve where dochdrkey=:1 and cny#=:2";*/

        $res = QueryResult(array($qry, $dochdrkey, GetMyCompany()));

        if ( !util_isPlatformDisabled() && IADimensions::isCustomDimensionsEnabled() ) {
            foreach ( $res as $idx => $glentry) {
                IADimensions::explodeCustomDimensionString($res[$idx]);
            }
        }

        return $res;
    }

    /**
     * @param int $dochdrkey
     *
     * @return bool
     */
    function Delete($dochdrkey)
    {
        // DANGER!! THIS IS NOT A NORMAL DELETE-BY-RECORD#, AS THERE IS NO RECORD#  :-(
        return ExecStmt(
            array("delete from deglsubtotresolve where dochdrkey=:1 and cny#=:2", 
                                $dochdrkey, GetMyCompany())
        );
    }
}

