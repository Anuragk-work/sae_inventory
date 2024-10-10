<?php
//=============================================================================
//
//	FILE:			DocentryGLResolveManager.cls
//	AUTHOR:			MJagadish
//	DESCRIPTION:	A manager class for the DOCUMENTENTRYGLRESOLVE entity
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

/**
 * Class DocumentEntryGLResolveManager
 */
class DocumentEntryGLResolveManager extends EntityManager
{
    /**
     * @param array $params
     */
    public function __construct($params = array())
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
        self::externalizeIfNecessary($values);
        return parent::regularAdd($values);
    }


    /**
     *  Older code passed in values for a direct SQL call.  Now that we are using EntityManager,
     *  turn any internal values into external values...
     *
     *
     * @param $values
     */
    protected static function externalizeIfNecessary(&$values)
    {
        if (!is_array($values[0] ?? null)) {
            $groupOfValues[0] = &$values;
        } else {
            $groupOfValues = &$values;
        }
        foreach ($groupOfValues as $index => $row) {
            if ($row['COGSPOSTING'] === 'T') {
                $groupOfValues[$index]['COGSPOSTING'] = 'true';
            } else if ($row['COGSPOSTING'] === 'F') {
                $groupOfValues[$index]['COGSPOSTING'] = 'false';
            }
            if ($row['COST_ADJ_NEEDED'] === 'T') {
                $groupOfValues[$index]['COST_ADJ_NEEDED'] = 'true';
            } else if ($row['COST_ADJ_NEEDED'] === 'F') {
                $groupOfValues[$index]['COST_ADJ_NEEDED'] = 'false';
            }
            if (isset($row['RECORD#'])) {
                $groupOfValues[$index]['RECORDNO'] = $row['RECORD#'];
            }
        }
    }


    /**
     *      Note: the NEW_GLENTRYKEY/OLD_GLENTRYKEY stuff doesn't appear to be used, but I'm not taking any chances
     *              and removing it....
     *
     * @param array $values
     *
     * @return bool
     */
    protected function regularSet(&$values)
    {
        // Note: before 10/1/2019, Set() only worked to update the glentrykey.  Let's make it a more general-purpose set....
        if (isset($values['NEW_GLENTRYKEY']) && isset($values['OLD_GLENTRYKEY'])) {
            return ExecStmt(
                array("UPDATE deglresolve set glentrykey=:1 where cny#=:2 and glentrykey=:3",
                    $values['NEW_GLENTRYKEY'], $values['CNY#'], $values['OLD_GLENTRYKEY'],)
            );
        } else {
            self::externalizeIfNecessary($values);
            return parent::regularSet($values);
        }
    }

    /**
     * Get a single record
     *
     * @param string $ID
     * @param array|null $fields
     *
     * @return array|false
     */
    function get($ID, $fields = null)
    {
        // PhpStorm inspection workaround
        if (1) {
            throw new Exception('Should not be reaching here!!');
        }
        return false;
    }

    /**
     * @param string $dochdrkey
     * @param bool   $costing
     *
     * @return array|false
     */
    function GetGLEntries($dochdrkey, $costing)
    {
        // GET DIMENSION KEYS
        $dimensionKeys = IADimensions::GetDimensionKeys();
        $glentryDimensionFieldStr = '';
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
            $glentryDimensionFieldStr .= 'glentry.customdimensions, ';
        }

        if ($costing) {
            $decWhereClause = " cogsposting = 'T' ";
        } else {
            $decWhereClause = " cogsposting = 'F' ";
        }

        $qry = "SELECT   glentry.record#, glentry.status, glentry.entry_date, glentry.batch#,
						 glentry.document, glentry.description, glaccount.acct_no glaccountkey,
						 glentry.basecurr, glentry.currency, glentry.user#,
						 deglresolve.amount, deglresolve.trx_amount, LOCATION.location_no location#,
						 department.dept_no dept#, glentry.line_no, glentry.tr_type dr_cr,
						 glentry.exch_rate_date, glentry.exch_rate_type_id,
						 glentry.exchange_rate, $glentryDimensionFieldStr
						 glentry.recon_date, deglresolve.orig_trtype, deglresolve.cogsposting, glentry.baselocation
					FROM glentry, baseaccount glaccount, deglresolve, departmentmst department, locationmst location
				   WHERE deglresolve.dochdrkey = :1
					 AND glentry.record# = deglresolve.glentrykey
					 AND deglresolve.cny#(+) = :2 
					 AND glentry.account# = glaccount.record#(+)
					 AND glaccount.cny#(+) = :2
					 AND glentry.dept# = department.record#(+)
					 AND department.cny#(+) = :2
					 AND glentry.location# = LOCATION.record#(+)
					 AND LOCATION.cny#(+) = :2
					 AND glentry.cny#(+) = :2
					 AND $decWhereClause
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
     *
     *      NOTE!  DANGER!  THIS IS NOT CORRECT, BUT I GUESS IS EXPECTED BY SOME CLIENTS.  This will delete ALL
     *              records for a transaction, not just the ones attached to a specific line, or a specific record.
     *
     *
     * @param int $dochdrkey
     *
     * @return bool
     */
    function Delete($dochdrkey)
    {
        return ExecStmt(
            array("delete from deglresolve where dochdrkey=:1 and cny#=:2",
                                $dochdrkey, GetMyCompany())
        );
    }


    /**
     *  If we are adding resolves, just go ahead and add them.  Otherwise, if we are upserting
     * the document, upsert the deglresolves by reading existing deglresolves, matching
     * as best we can, and adding/setting them.  Delete any remaining deglresolves.
     *
     * Note: on advice from Senthil, made this 'static'
     *
     * @param array         $deGlResolves           array of deglresolves we want, by docentrykey
     *
     * @return bool                                 did it work?
     *
     */
    static function addOrUpsert($deGlResolves)
    {
        $docentryGLResolveMgr = Globals::$g->gManagerFactory->getManager('documententryglresolve');
        DocumentManager::updatingEntity($docentryGLResolveMgr->_entity);
        $matchmaker = new Matchmaker($docentryGLResolveMgr, Matchmaker::ALLOW_IGNORE, Matchmaker::DELETE_BY_RECORDNO, [], [], false ); // no dimensions
        $matchmaker->setNullMeans( 'COST_ADJ_NEEDED', 'false');

        $ok = true;
        foreach ($deGlResolves as $oneDocEntry => $oneDocEntrysRecords) {
            foreach ($oneDocEntrysRecords as $index => $values) {
                self::externalizeIfNecessary($oneDocEntrysRecords[$index]); // now the match is in external format
            }
            // if upsert is in progress, look for existing records, otherwise don't
            $ok = $ok && $matchmaker->upsert($oneDocEntrysRecords, (DocumentManager::$upsertFeaturInUse ? 'DOCENTRYKEY' : ''), $oneDocEntry);
        }
        return $ok;
    }



}

