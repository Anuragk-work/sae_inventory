<?php

/**
 * Manager file for the CogsClosedJe object
 *
 * LICENSE:
 * (C)2000-2018 Intacct Corporation, All Rights Reserved
 *
 * Intacct Corporation Proprietary Information.
 * This document contains trade secret data that belongs to Intacct
 * corporation and is protected by the copyright laws. Information herein
 * may not be used, copied or disclosed in whole or part without prior
 * written consent from Intacct Corporation.
 *
 * @author    Roger Collins, Ted Pohlman
 * @copyright 2018 Intacct Corporation All, Rights Reserved
 */


/**
 * CogsClosedJe Doc Comment
 *
 * @category  Cls
 * @package   Source/inventory
 * @author    Roger Collins
 * @copyright 2018 Intacct Corporation, All Rights Reserved
 */
class CogsClosedJeManager extends EntityManager
{

    /** @var array $Gladjrecord */
    private $Gladjrecord = [];

    /**
     * @var array $updatevalues
     */
    private $updatevalues = [];

    /**
     * @var array $commitStatus
     */
    public $commitStatus = [];


    /**
     * @var array $needsadjustment
     */
    public $needsadjustment = [];


    /**
     * CogsClos656
     * edJe constructor.
     *
     * @param array $params
     */
    function __construct($params = [])
    {
        parent::__construct($params);
    }


    /**
     *  'add', or from the API: 'Create'.
     *  This is used to post or un-post values
     *
     * note: unlike a normal EntityManager add, here we do not have a specific disk file,
     *      instead we use the GL posting/unposting mechanisms
     *
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $ok = true;
        $gErr = Globals::$g->gErr;
        $this->commitStatus =
            [
                'SUCCESS' => 0,
                'FAIL'    => 0,
                'TOTAL'   => 0,
            ];
        $pol = 'inv/lists/cogsclosedje/create';
        if (!CheckAuthorization(GetOperationId($pol), 1))
        {
            $msg = "No adjustments were posted because you don’t have the appropriate permission.<br> Ask your system administrator for assistance.";
            $gErr->addIAError('INV-0302', __FILE__ . ':' . __LINE__, $msg, []);
            $this->commitStatus['MESSAGE'][] = $msg;
            return false;
        }


        // get manual adjustment flag, if present
        $manualResolve = false;
        $values['MANUALRESOLVE'] = $values['MANUAL_ADJUSTMENT'];
        if (!is_null($values['MANUALRESOLVE']) && ($values['MANUALRESOLVE'] !== ''))
        {
            // check for valid value
            switch ($values['MANUALRESOLVE'])
            {
                case 'T';
                case 't';
                case 'true';
                case 'TRUE';
                    $manualResolve = true;

                    break;
                case 'F':
                case 'f':
                case 'false':
                case 'FALSE':
                    $manualResolve = false;
                    break;
                default:
                    $manresolve = $values['MANUALRESOLVE'];
                    Globals::$g->gErr->addIAError(
                        'INV-0303',
                        __FILE__ . ':' . __LINE__,
                        "invalid value for MANUALRESOLVE $manresolve.", ['MANRESOLVE' => $manresolve]
                    );
                    $ok = false;
                    break;
            }
        }

        if ($ok && !empty($values["RECORDNO"]))
        {   // could be ONE record number, could be dozens
            $numberofsuccess = 0;
            $numberoffail = 0;
            $records = (is_array($values["RECORDNO"]) ? $values["RECORDNO"] : [$values["RECORDNO"]]);
            foreach ($records as $record)
            {
                $ok = true;
                $sourcerecord = "CogsClosedJeManager:add:rec# $record";
                $this->_QM->beginTrx($sourcerecord);

                $recordsToAdd = QueryResult(
                    [
                        "SELECT d.glentrykey, c.difference, c.recordno, d.DOCHDRKEY, d.record# drecordno 
                          FROM deglresolve d, v_cogsresolve c 
                          WHERE d.cny# = :1 AND d.docentrykey = :2  and c.cny# = d.cny# and c.recordno = d.DOCENTRYKEY and  c.cost_adj_needed = :3 and  cogsposting = :4",
                        GetMyCompany(),
                        $record,
                        'T',
                        'T',
                    ]
                );

                if (count($recordsToAdd) != 2)
                {
                    $ok = false;
                    $msg = "There is a problem retrieving the GL posting entries.  <br> The entries may have been deleted by another user";
                    Globals::$g->gErr->addIAError('INV-0304', __FILE__ . ':' . __LINE__, $msg, []);
                    $this->commitStatus['MESSAGE'][] = $msg;
                }
                $existingGLEntry1 = $recordsToAdd[0]['GLENTRYKEY'];
                $existingGLEntry2 = $recordsToAdd[1]['GLENTRYKEY'];

                if ($ok)
                {
                    if (($existingGLEntry1 == NULL) || ($existingGLEntry2 == NULL))
                    {
                        $msg = "Record $record does not exist. Enter a valid record number.";
                        Globals::$g->gErr->addIAError('INV-0305', __FILE__ . ':' . __LINE__, $msg, ['RECORD' => $record]);
                        $ok = false;
                    }
                    else
                    {
                        // Get the DocEntry's exchange rate, as the DocEntryCost records have no TRX_COST!
                        $qry[0] = "Select exchange_rate, locationkey from docentry where cny# = :1 and record# = :2";
                        $qry[1] = GetMyCompany();
                        $qry[2] = (int)($record);   // make sure it is a number and not <RECORDNO>Aria Stark</RECORDNO>
                        $rtn = QueryResult($qry);   // same parameters as above
                        if (($rtn === false) || (count($rtn) == 0))
                        {
                            Globals::$g->gErr->addIAError('INV-0004', __FILE__ . ':' . __LINE__, "Unable to find the exchange rate for this adjustment.", []);
                            $ok = false;
                        }
                        else
                        {
                            // Get the current DocEntryCost records (the desired amount)
                            // note: unbelievably, there is no trx_cost here
                            $exchangeRate = ($rtn[0]['EXCHANGE_RATE'] != 0.0) ? $rtn[0]['EXCHANGE_RATE'] : 1.0; // missing exchange rate will be treated as 1
                            $locationKey = $rtn[0]['LOCATIONKEY'];

                            $postingDate = $values["POSTINGDATE"] ?? GetCompanyOpenDate(false,
                                    $locationKey); // false means to force the lookup for the location, if one

                            $ok = $ok && $this->checkOpenBooks($postingDate, $locationKey, 'post');


                            if ($ok)
                            {
                                {
                                    $newCost = $recordsToAdd[0]['DIFFERENCE'];
                                    $newTrxCost = $recordsToAdd[0]['DIFFERENCE'] * $exchangeRate;

                                    // get the amount to post and the exchange amount
                                    $amountToPost = iround($newCost, 2);
                                    $trx_amountToPost = iround($newTrxCost, 2);

                                    $ok = $this->addCogsPosting(
                                        $postingDate,
                                        $amountToPost,
                                        $trx_amountToPost,
                                        $existingGLEntry1,
                                        $existingGLEntry2,
                                        $record,
                                        $manualResolve,
                                        $recordsToAdd);
                                }
                            }
                        }
                    }
                }
                if ($ok)
                {
                    // success
                    $numberofsuccess++;
                    $ok = $this->_QM->commitTrx($sourcerecord);
                }
                else
                {
                    // fail
                    $numberoffail++;
                    $this->_QM->rollbackTrx($sourcerecord);
                }
            }

            $this->commitStatus['SUCCESS'] = $numberofsuccess;
            $this->commitStatus['FAIL'] = $numberoffail;
            $this->commitStatus['TOTAL'] = $numberofsuccess + $numberoffail;
        }
        else
        {
            $gErr->addIAError('INV-0005', __FILE__ . ':' . __LINE__, "Enter a valid record number.", []);
            $ok = false;
        }

        return $ok;
    }


    /**
     * @param string $ID
     * @param string $fields
     * @return array|false
     */
    function get($ID, $fields = null)
    {
        $IDval = intval($ID); // make sure this is just a number and not some injection

        $obj = parent::get($IDval, $fields);
        return $obj;
    }

    /**
     * Return a list of entities
     *
     * @param array $params a structure used to build the custom query
     * @param bool $_crosscny if true do not add the var.cny# = ... code
     * @param bool $nocount don't generate a count column
     *
     * @return array[] $newResult  result of query
     */
    function GetList($params = [], $_crosscny = false, $nocount = true)
    {
        // only posting items
        $params['filters'][0][] = ['DEGLRESOLVE_COGSPOSTING', '=', 'T'];

        $needsadjustment = $this->needsadjustment;
        if (!empty($needsadjustment))
        {
            //    needsadjustment has been set for this query
            //    add it to the params
            //    this is required even though the list of  record numbers being passed in
            //    have already had 'needsadjustment = 'T/F'' filtering, because the way the
            //    view works, it can return duplicate record numbers.
            //    this is not a bug, it is required because of the way deglresolve and cogsresolve talbe interact.
            $params['filters'][0][] = [$needsadjustment[1], $needsadjustment[2], $needsadjustment[3]];
            $this->needsadjustment = null;
        }

        $list = parent::GetList($params, $_crosscny, $nocount);
        return $list;
    }

    /**
     * @param array $values
     * @return bool
     */
    function setByRef(&$values)
    {
        $gErr = Globals::$g->gErr;
        $pol = 'inv/lists/cogsclosedje/create';
        if (!CheckAuthorization(GetOperationId($pol), 1))
        {
            $adj = $this->updatevalues['newValues']['MANUAL_ADJUSTMENT'];
            switch ($adj)
            {
                case 'true':
                    $mark = 'marked';
                    break;
                case 'false';
                    $mark = 'unmarked';
                    break;
                default:
                    $mark = 'marked/unmarked';
                    break;
            }
            $msg = "No adjustments were $mark because you don’t have the appropriate permission.<br> Ask your system administrator for assistance.";
            $gErr->addIAError('INV-0306', __FILE__ . ':' . __LINE__, $msg, ['MARK' => $mark]);
            $this->commitStatus['MESSAGE'][] = $msg;
            return false;
        }


        $result = true;
        $newValues = $this->updatevalues['newValues'];

        $source = "CogsClosedJeManager:setByRef";
        $this->_QM->beginTrx($source);

        // setting manual adjustment?`
        if (!is_null($newValues['MANUAL_ADJUSTMENT']))
        {
            $result = $this->setManualResolve($values);
        }

        if ($result)
        {
            // do the default action
            $result = parent::setByRef($values);
        }

        if ($result)
        {
            $result = $this->_QM->commitTrx($source);
        }
        if (!$result)
        {
            $this->_QM->rollbackTrx($source);
        }

        return $result;
    }


    /**
     * @param array $newValues
     * @param array $existingValues
     * @return bool
     */
    function API_ValidateObject(&$newValues, $existingValues)
    {
        // do defalut action
        $result = parent:: API_ValidateObject($newValues, $existingValues);

        $this->updatevalues = [
            'newValues'      => $newValues,
            'existingValues' => $existingValues,
        ];

        if ($result)
        {
            // doing a manual adjustment?
            if (!is_null($newValues['MANUAL_ADJUSTMENT']))
            {
                // setting manual adjustment
                $manualResolve = $newValues['MANUAL_ADJUSTMENT'];

                switch ($manualResolve)
                {
                    case 'T':
                        if ($existingValues['NEEDSADJUSTMENT'] == 'F')
                        {
                            // already resolved.
                            $gErr = Globals::$g->gErr;
                            $msg = 'Record does not need adjustment.';
                            $gErr->addIAError('INV-0307', __FILE__ . ':' . __LINE__, $msg, []);
                            $result = false;
                            break;
                        }

                        break;
                    case 'F':
                        if ($existingValues['NEEDSADJUSTMENT'] == 'T')
                        {
                            // already  resolved.
                            $gErr = Globals::$g->gErr;
                            $msg = 'Record already resolved!';
                            $gErr->addIAError('INV-0308', __FILE__ . ':' . __LINE__, $msg, []);
                            $result = false;
                            break;
                        }
                        if ($existingValues['MANUAL_ADJUSTMENT'] == 'F')
                        {
                            // already not marked as manualy adjusted.
                            $gErr = Globals::$g->gErr;
                            $msg = 'Record not marked as being manually resolved!';
                            $gErr->addIAError('INV-0309', __FILE__ . ':' . __LINE__, $msg, []);
                            $result = false;
                            break;
                        }
                        break;

                    default:
                        // nothing to do here
                        break;
                }
            }

        }
        return $result;
    }


    /**
     * @param array $values
     * @return bool
     */
    function setManualResolve($values)
    {
        $result = true;

        $source = "CogsClosedJeManager:setManualResolve";
        $this->_QM->beginTrx($source);

        $manualResolve = $values['MANUAL_ADJUSTMENT'];

        switch ($manualResolve)
        {
            case 'T';
            case 't';
            case 'true';
            case 'TRUE';
                // add manual resolve
                $result = $this->add($values);
                break;

            case 'F':
            case 'f':
            case 'false':
            case 'FALSE':
                $deleteId = $values['RECORDNO'];
                // remove manual resolve
                $result = $this->Delete($deleteId);
                break;

        }
        if ($result)
        {
            $result = $this->_QM->commitTrx($source);
        }
        if (!$result)
        {
            $this->_QM->rollbackTrx($source);
        }

        return $result;
    }


    /**
     * Delete a record from the database (override)
     *
     * This implementation is usually sufficient for single table objects
     *
     * @param string|int $ID the unique posting id returned from the readByQuery call
     *
     * @return bool
     */
    public function Delete($ID)
    {
        $ok = true;
        $this->commitStatus =
            [
                'SUCCESS' => 0,
                'FAIL'    => 0,
                'TOTAL'   => 0,
            ];

        $gErr = Globals::$g->gErr;
        $pol = 'inv/lists/cogsclosedje/delete';
        if (!CheckAuthorization(GetOperationId($pol), 1))
        {
            $msg = "No adjustments were deleted because you don’t have the appropriate permission.<br> Ask your system administrator for assistance.";
            $gErr->addIAError('INV-0310', __FILE__ . ':' . __LINE__, $msg, []);
            $this->commitStatus['MESSAGE'][] = $msg;
            return false;
        }


        // often Delete is passed a record number.  Here, though, I expect a number in this format:
        // nnnn--nnnnnnnn
        // where the leading number is the DocEntry record number, and the trailing number is the 'posting id',
        // which narrows down the post to, usually, just two records.  If more than two, it will be pairs of records.
        if ($ID == '')
        {
            $msg = "A posting adjustment ID is needed.  It is in the format nnnn--nnnn and comes from a ReadByQuery with \"NEEDSADJUSTMENT='false'\"";
            Globals::$g->gErr->addIAError('INV-0311', __FILE__ . ':' . __LINE__, $msg, []);
            return false;
        }

        $records = $ID;
        $records = (is_array($records) ? $records : [$records]);
        $numberofsuccess = 0;
        $numberoffail = 0;
        foreach ($records as $record)
        {
            $ok = true;
            $sourcerecord = "CogsClosedJeManager:Delete:rec# $record";
            $this->_QM->beginTrx($sourcerecord);
            list($docEntryRecordNumber, $postingID) = explode("--", $record);

            $qry = [];
            $qry[0] = "Select glentrykey, orig_trtype from cogsresolve where cny# = :1 and docentrykey = :2 and postingid = : 3 order by amount";
            $qry[1] = GetMyCompany();
            $qry[2] = (int)($docEntryRecordNumber);
            $qry[3] = (int)($postingID);
            $rtn = QueryResult($qry);
            if (($rtn === false) || (count($rtn) == 0))
            {
                Globals::$g->gErr->addIAError(
                    'INV-0312',
                    __FILE__ . ':' . __LINE__,
                    "Posting adjustment $ID does not exist.  It comes from a ReadByQuery with \"NEEDSADJUSTMENT='false'\"", ['ID' => $ID]
                );
                $ok = false;
            }
            else
            {
                $cache = [];
                foreach ($rtn as $oneCogsResolve)
                {
                    $cache[$oneCogsResolve['ORIG_TRTYPE']][] = $oneCogsResolve['GLENTRYKEY'];
                }
                $index = 0;
                while (isset($cache[-1][$index]))
                {
                    $ok = $ok && $this->removeCogsPosting($cache[-1][$index], $cache[+1][$index]);
                    $index++;
                }
                // if it succeeded, remove all the records that match the query result
                if ($ok)
                {
                    $ok = $ok && ExecStmt(["DELETE FROM cogsresolve WHERE cny# = :1 and docentrykey = :2 and postingid = : 3",
                            GetMyCompany(), (int)($docEntryRecordNumber), (int)($postingID)]);
                }
            }
            // update the existing DeGlResolve records
            $ok = $ok && ExecStmt(["UPDATE deglresolve set COST_ADJ_NEEDED = 'T' where cny# = :1 and docentrykey = :2 and COGSPOSTING = 'T' ", GetMyCompany(), $docEntryRecordNumber]);
            if ($ok)
            {
                // success
                $numberofsuccess++;
                $ok = $this->_QM->commitTrx($sourcerecord);
            }
            else
            {
                // fail
                $numberoffail++;
                $this->_QM->rollbackTrx($sourcerecord);
            }
        }
        $this->commitStatus['SUCCESS'] = $numberofsuccess;
        $this->commitStatus['FAIL'] = $numberoffail;
        $this->commitStatus['TOTAL'] = $numberofsuccess + $numberoffail;

        return $ok;
    }

    /**
     * Delete an object from Web Services API (override)
     *  This is called BEFORE Delete, above, so I had to interceed here as well
     *
     * @param string $recordno The unique record number for the object
     *
     * @return bool success or failure
     */
    function API_Delete($recordno)
    {
        // do checking like entitymanager
        $gErr = Globals::$g->gErr;
        if (empty($recordno))
        {
            $msg = "At least one object key must be supplied to delete.";
            $gErr->addIAError('INV-0313', __FILE__ . ':' . __LINE__, $msg);
            return false;
        }

        //  Validate operation.
        if (!$this->API_Validate(API_DELETE, $values))
        {
            return false;
        }
        //  Delete reads data, but never returns it - suppress AAT references.
        AdvAuditTracking::setManagedTracking(false);

        // disable validation warnings since it doesn't make sense to throw warnings in API
        $prevWarningValidation = $this->getWarningValidation();
        $this->disableWarningValidation();

        $ret = $this->Delete($recordno);

        if ($prevWarningValidation)
        {
            $this->enableWarningValidation();
        }
        return $ret;
    }


    /**
     * @param array $glrecord
     * @param array $params
     * @return array
     */
    private function createheader(&$glrecord, &$params)
    {
        $header = $this->getTransactionTemplate();

        $header['ADJ'] = $glrecord['ADJ'];
        $header['asset_disposalglbatch'] = $glrecord['asset_disposalglbatch'];
        $header['BALANCE'] = $glrecord['BALANCE'];
        $header['BASELOCATION'] = $glrecord['BASELOCATION'];
        $header['BASELOCATION_NAME'] = $glrecord['BASELOCATION_NAME'];
        $header['BASELOCATION_NO'] = $glrecord['BASELOCATION_NO'];
        $header['BATCH_DATE'] = $params['BATCH_DATE'];
        $header['BATCH_TITLE'] = $glrecord['BATCH_TITLE'];
        $header['BATCHNO'] = null;
        $header['CHILDENTITY'] = $glrecord['CHILDENTITY'];
        $header['CONTRACTSCHEDULEENTRYKEY'] = $glrecord['CONTRACTSCHEDULEENTRYKEY'];
        $header['CONTRACTSCHEDULEKEY'] = $glrecord['CONTRACTSCHEDULEKEY'];
        $header['ENTRIES'] = [];
        $header['GLBATCHOutOfService'] = $glrecord['GLBATCHOutOfService'];
        $header['JOURNAL'] = $params['CLOSEDPERIODJOURNAL'];
        $header['JOURNAL_BILLABLE'] = $glrecord['JOURNAL_BILLABLE'];
        $header['JOURNALKEY'] = $glrecord['JOURNALKEY'];
        $header['LOCATIONKEY'] = $glrecord['LOCATIONKEY'];
        $header['MEGAENTITYID'] = $glrecord['MEGAENTITYID'];
        $header['MEGAENTITYKEY'] = $glrecord['MEGAENTITYKEY'];
        $header['MEGAENTITYNAME'] = $glrecord['MEGAENTITYNAME'];
        $header['MODULE'] = $glrecord['MODULE'];
        $header['PRBATCHKEY'] = $glrecord['PRBATCHKEY'];
        $header['PRBATCHRECTYPE'] = $glrecord['PRBATCHRECTYPE'];
        $header['RASSET'] = $glrecord['RASSET'];
        $header['RASSET_ADJUSTMENT'] = $glrecord['RASSET_ADJUSTMENT'];
        $header['RASSET_CLASS'] = $glrecord['RASSET_CLASS'];
        $header['RAsset_Manual_Adjustment'] = $glrecord['RAsset_Manual_Adjustment'];
        $header['RAssetClass_Manual_Adjustment'] = $glrecord['RAssetClass_Manual_Adjustment'];
        $header['RASSETOUTOFSERVICE'] = $glrecord['RASSETOUTOFSERVICE'];
        $header['RDEPRECIATION_SCHEDULE'] = $glrecord['RDEPRECIATION_SCHEDULE'];
        $header['RECORDNO'] = null;
        $header['REFERENCENO'] = $glrecord['REFERENCENO'];
        $header['REVERSED'] = $glrecord['REVERSED'];
        $header['REVERSEDFROM'] = $glrecord['REVERSEDFROM'];
        $header['REVERSEDKEY'] = $glrecord['REVERSEDKEY'];
        $header['rglbatch'] = $glrecord['rglbatch'];
        $header['RRSENTRYKEY'] = $glrecord['RRSENTRYKEY'];
        $header['RRSKEY'] = $glrecord['RRSKEY'];
        $header['SCHOPKEY'] = $glrecord['SCHOPKEY'];
        // $header['STATE'] = $glrecord['STATE'];
        $header['SUPDOCID'] = $glrecord['SUPDOCID'];
        $header['TEMPLATEKEY'] = $glrecord['TEMPLATEKEY'];

        return $header;

    }


    /**
     * @return array
     */
    private function getTransactionTemplate()
    {
        // journal fields initial value
        $journalEntryTemplate = [
            '_isdraft'                      => true,
            'ADJ'                           => 'F',
            'APPROVEDECLINEJEWITHCOMMENT'   => null,
            'AUTOBALANCE_ENTRIES'           => null,
            'BATCH_DATE'                    => "",
            'BATCH_TITLE'                   => "test  account allocation",
            'CONFIRM_SAVE_ORIGINAL_JE'      => null,
            'CONFIRM_UPDATE_EXC_DATE_LINES' => null,
            'CONFIRM_UPDATE_MEMO_LINES'     => null,
            'CONFIRM_UPDATE_ORIGINAL_JE'    => null,
            'CREATE_OR_SAVE_ACTION'         => true,
            'GLBATCHHISTORY'                => null,
            'INTER_ENTITY_ENTRIES'          => null,
            'INTER_ENTITY_ENTRIES_TOTALS'   => [],
            'JOURNAL'                       => "",
            'MODULE'                        => "2.GL",
            'RECORD_URL'                    => "",
            'REVERSE_ENTRY_PAGE'            => null,
            'STATE'                         => "",

            'ENTRIES_CAPTION'            => [],
            'AUTOBALANCE_ENTRIES_TOTALS' => [],
            'DYNAMIC_HELP_INFORMATION'   => [
                'DYNAMIC_HELP_INFORMATION_FIELDS'      => null,
                'DYNAMIC_HELP_INFORMATION_SECTIONS'    => null,
                'DYNAMIC_HELP_INFORMATION_STD_BUTTONS' => null,
            ],

            'ENTRIES_TOTALS'      => [],
            'SPLIT_DEFAULTS_PAGE' => [
                'FLOAT_SPLIT'         => [
                    0 => [
                        '__dummy'    => "",
                        '_isNewLine' => true,
                    ],
                    1 => [
                        '__dummy'    => "",
                        '_isNewLine' => true,
                    ],
                ],
                'FLOAT_SPLIT_CAPTION' => [],
                'FLOAT_SPLIT_TOTALS'  => [],
            ],
            'USERINFO'            => [
                'ADMIN'            => "",
                'ADMINPASSWORD'    => "",
                'CHATTER_DISABLED' => "false",
                'CONTACTINFO'      => [
                    'CELLPHONE'   => "",
                    'COMPANYNAME' => "",
                    'CONTACTNAME' => "",
                    'EMAIL1'      => "",
                    'EMAIL2'      => "",
                    'FAX'         => "",
                    'FIRSTNAME'   => "",
                    'INITIAL'     => "",
                    'LASTNAME'    => "",
                    'MAILADDRESS' => [
                        'ADDRESS1'    => "",
                        'ADDRESS2'    => "",
                        'CITY'        => "",
                        'COUNTRY'     => "",
                        'COUNTRYCODE' => "",
                        'STATE'       => "",
                        'ZIP'         => "",
                    ],
                    'PAGER'       => "",
                    'PHONE1'      => "",
                    'PHONE2'      => "",
                    'PREFIX'      => "",
                    'PRINTAS'     => "",
                    'URL1'        => "",
                    'URL2'        => "",
                ],
                'CONTACTKEY'       => "",

                'CREATEDBY'           => "",
                'CSQANSWER'           => "",
                'CSQUESTION'          => "",
                'DESCRIPTION'         => "",
                'LOGINDISABLED'       => "false",
                'MEGAENTITYID'        => "",
                'MEGAENTITYKEY'       => "",
                'MEGAENTITYNAME'      => "",
                'MFA_ENABLED'         => "false",
                'MFA_INFO'            => "",
                'MFA_NOTRUST'         => "none",
                'MODIFIEDBY'          => "",
                'PWDNEVEREXPIRES'     => "false",
                'PWDQLYNOTENFORCED'   => "false",
                'RECORD#'             => "",
                'RECORDNO'            => "",
                'RESETPASSWORD'       => "false",
                'RESETUSERPASSWORD'   => "",
                'SSO_COMPANY_ENABLED' => "Enabled",
                'SSO_ENABLED'         => "false",
                'SSO_FEDERATED_ID'    => "",
                'STATUS'              => "active",
                'UNRESTRICTED'        => "true",
                'USERTYPE'            => "",
                'VISIBLE'             => "true",
                'WHENCREATED'         => "",
                'WHENMODIFIED'        => "",
            ],
        ];

        return $journalEntryTemplate;
    }

    /**
     * @param array $entry
     * @param array $params
     * @return array
     */
    private function createline(&$entry, &$params)
    {
        // create a single line for a transaction

        // get the line number
        $lineno = $params['LINECOUNT']++;

        // starting line template
        $journalEntry = [
            '_isNewLine'   => true,
            'SPLIT_TOTALS' => [],
            'SPLIT'        => [],
        ];

        // determine if this is a DB or CR
        // create the appropriate entry values
        // if amount is negative need to reverse the debit/credit
        $amount = $params['AMOUNT'];
        if (($entry['TR_TYPE'] > 0) == (($amount >= 0)))
        {
            $DbCrTag = 'DEBIT';
            $TxnTag = 'TRX_DEBIT';
            $TrtyppeValue = 1;
        }
        else
        {
            $DbCrTag = 'CREDIT';
            $TxnTag = 'TRX_CREDIT';
            $TrtyppeValue = -1;
        }

        // update fields with passed in values
        // make amount positive
        $amount = ($amount >= 0) ? $amount : -$amount;
        $journalEntry['AMOUNT'] = $amount;
        $journalEntry[$DbCrTag] = $amount;
        $journalEntry['TRX_AMOUNT'] = $amount;
        $journalEntry[$TxnTag] = $amount;
        $journalEntry['TR_TYPE'] = $TrtyppeValue;

        $journalEntry['BATCH_DATE'] = $params['BATCH_DATE'];
        $journalEntry['LINE_NO'] = '' . $lineno;


        // update the rest of the fleds from the passed in entry
        $journalEntry['ENTRY_DATE'] = $entry['ENTRY_DATE'];

        $journalEntry['ACCOUNTNO'] = $entry['ACCOUNTKEY'];
        $journalEntry['ACCOUNT#'] = $entry['ACCOUNTKEY'];

        $journalEntry['BASECURR'] = $entry['CURRENCY'];
        $journalEntry['CURRENCY'] = $entry['CURRENCY'];
        $journalEntry['DESCRIPTION'] = $entry['DESCRIPTION'];
        $journalEntry['DOCUMENT'] = $entry['DOCUMENT'];

        $journalEntry['LOCATIONKEY'] = $entry['LOCATIONKEY'];
        $journalEntry['LOCATIONNAME'] = $entry['LOCATIONNAME'];
        $journalEntry['LOCATION#'] = $entry['LOCATIONKEY'];

        $journalEntry['DEPARTMENTKEY'] = $entry['DEPARTMENTKEY'];
        $journalEntry['DEPT#'] = $entry['DEPARTMENTKEY'];
        IADimensions::CopyIADimensionValues($entry, $journalEntry);

        $journalEntry['ADJ'] = $entry['ADJ'];
        $journalEntry['ALLOCATION'] = $entry['ALLOCATION'];
        $journalEntry['ALLOCATIONKEY'] = $entry['ALLOCATIONKEY'];
        $journalEntry['BASELOCATION'] = $entry['BASELOCATION'];
        $journalEntry['BASELOCATION_NAME'] = $entry['BASELOCATION_NAME'];
        $journalEntry['BASELOCATION_NO'] = $entry['BASELOCATION_NO'];
        $journalEntry['BATCHTITLE'] = $entry['BATCHTITLE'];
        $journalEntry['BILLABLE'] = $entry['BILLABLE'];
        $journalEntry['BILLED'] = $entry['BILLED'];
        $journalEntry['EXCH_RATE_DATE'] = $entry['EXCH_RATE_DATE'];
        $journalEntry['EXCH_RATE_TYPE_ID'] = $entry['EXCH_RATE_TYPE_ID'];
        $journalEntry['EXCHANGE_RATE'] = $entry['EXCHANGE_RATE'];
        $journalEntry['GLDIMEND_USER_DIRECTIONAL'] = $entry['GLDIMEND_USER_DIRECTIONAL'];
        $journalEntry['IETYPE'] = $entry['IETYPE'];
        $journalEntry['PARENTGLENTRYKEY'] = $entry['PARENTGLENTRYKEY'];
        $journalEntry['STATISTICAL'] = $entry['STATISTICAL'];
        $journalEntry['TIMEPERIOD'] = $entry['TIMEPERIOD'];
        $journalEntry['TMPLENTRYKEY'] = $entry['TMPLENTRYKEY'];
        $journalEntry['UNITS'] = $entry['UNITS'];

        // don't copy these fileds
        $journalEntry['CLEARED'] = null;
        $journalEntry['CLRDATE'] = null;
        $journalEntry['CREATEDBY'] = null;
        $journalEntry['RECON_DATE'] = null;
        $journalEntry['RECORDNO'] = null;
        $journalEntry['STATE'] = null;

        // find custom fields,dimensions
        $regex = "/(GLDIM|CF_GLENTRY_|RGLDIM\d+_).+/";
        foreach ($entry as $lineKey => $lineValue)
        {
            if (preg_match($regex, $lineKey))
            {
                // Found a match!
                $journalEntry[$lineKey] = $entry[$lineKey];
            }
        }

        return $journalEntry;
    }




    //  ***********************************************************************************************************
    //  ***********************************************************************************************************
    //
    //      UPDATE COGS
    //
    //  ***********************************************************************************************************
    //  ***********************************************************************************************************

    /**
     *      add Cogs Posting - add gl entries to make an existing DocEntry record correct
     *  Scenario: the cost of a sale/transfer-out has changed, but the sale is in a closed period or it's batch has been closed.
     *  Here, we have the delta amount (the amount to make COGS correct) and two sample gl entries to use for fields
     *  (these are two of the original gl posting records, from DeGlResolve records)
     *
     * @param string $postingDate the date on which to post the new entries
     * @param float $amountToPost base-currency amount to post
     * @param float $trx_amountToPost transaction-currency amount to post
     * @param int $existingGLEntry1 example existing gl entry with one account
     * @param int $existingGLEntry2 example existing gl entry with the other account
     * @param int $docEntryRecordNo the DocEntry record#
     *
     * @param string $manualResolve
     * @param array $recordsToAdd
     * @return bool     was this successful?
     */
    public function addCogsPosting($postingDate, $amountToPost, $trx_amountToPost, $existingGLEntry1, $existingGLEntry2, $docEntryRecordNo, $manualResolve, $recordsToAdd)
    {
        // start a transaction
        $ok = true;

        $manualEntry = $manualResolve == true ? 'T' : 'F';
        $ok = $ok && $this->postCogsGLEntry($postingDate, $amountToPost, $trx_amountToPost, $existingGLEntry1, $existingGLEntry2, $docEntryRecordNo, $manualResolve);


        if ($ok)
        {
            // add those two glentry records to disk, and whatever else the gl system demands (create a batch?  something else?)
            //   create a COGSPosting record with the two new glentry keys and the DocEntry record# and the rest
            $dochdrkey = $recordsToAdd[0]['DOCHDRKEY'];

            $glentrykey0 = $this->Gladjrecord['ENTRIES'][0]['RECORDNO'];
            $orig_trtype0 = $this->Gladjrecord['ENTRIES'][0]['TR_TYPE'];
            $currency0 = $this->Gladjrecord['ENTRIES'][0]['CURRENCY'];

            $glentrykey1 = $this->Gladjrecord['ENTRIES'][1]['RECORDNO'];
            $orig_trtype1 = $this->Gladjrecord['ENTRIES'][1]['TR_TYPE'];
            $currency1 = $this->Gladjrecord['ENTRIES'][1]['CURRENCY'];

            $postingID = $this->Gladjrecord['POSTINGID'];


            $deglresolvekey0 = $recordsToAdd[0]['DRECORDNO'];
            $deglresolvekey1 = $recordsToAdd[1]['DRECORDNO'];


            $ok = $ok && ExecStmt(
                    [
                        "INSERT INTO cogsresolve 
                        (cny#, dochdrkey, docentrykey, glentrykey, amount, currency, trx_amount, orig_trtype, postingid, manual_adjustment, deglresolvekey )
                         VALUES (:1,:2,:3,:4,:5,:6,:7,:8,:9,:10,:11)",
                        GetMyCompany(),
                        $dochdrkey,
                        $docEntryRecordNo,
                        $glentrykey0,
                        $amountToPost,
                        $currency0,
                        $trx_amountToPost,
                        $orig_trtype0,
                        $postingID,
                        $manualEntry,
                        $deglresolvekey0,
                    ]
                );

            $ok = $ok && ExecStmt(
                    [
                        "INSERT INTO cogsresolve 
                            (cny#, dochdrkey, docentrykey, glentrykey, amount, currency, trx_amount, orig_trtype, postingid,manual_adjustment, deglresolvekey ) 
                            VALUES (:1,:2,:3,:4,:5,:6,:7,:8,:9,:10,:11)",
                        GetMyCompany(),
                        $dochdrkey,
                        $docEntryRecordNo,
                        $glentrykey1,
                        $amountToPost,
                        $currency1,
                        $trx_amountToPost,
                        $orig_trtype1,
                        $postingID,
                        $manualEntry,
                        $deglresolvekey1,
                    ]);

            // update the existing DeGlResolve records that got us here:
            $ok = $ok && ExecStmt(["UPDATE deglresolve set COST_ADJ_NEEDED = 'F' where cny# = :1 and docentrykey = :2 and COGSPOSTING = 'T' ", GetMyCompany(), $docEntryRecordNo]);
        }
        return $ok;
    }


    /**
     *      remove Cogs Posting - remove or counter-post gl entries that had been made with 'addCogsPosting', above.
     *  Scenario: a prior run had called 'addCogsPosting()', above, and created COGS postings.
     *  Here, the customer has asked us to remove that specific post for that specific amount
     *
     * @param int $existingGLEntry1 existing gl entry with one account that we want to remove or counter-post
     * @param int $existingGLEntry2 existing gl entry with the other account
     *
     * @return bool     was this successful?
     */
    public function removeCogsPosting($existingGLEntry1, $existingGLEntry2)
    {

        $glentryKeys = [$existingGLEntry1, $existingGLEntry2];
        global $gManagerFactory;
        /** @var GLBatchManager $glbatchMgr */
        $glbatchMgr = $gManagerFactory->getManager('glbatch');
        $glentryMgr = $gManagerFactory->getManager('glentry');
        $ok = true;

        $source = "CogsClosedJeManager::removeCogsPosting";
        $ok = $ok && $this->beginTrx($source);

        $params = [
            'selects' => ['BATCHNO', 'LOCATION#', 'ENTRY_DATE'],
            'filters' => [
                [
                    [
                        'recordno', 'in', $glentryKeys,
                    ],
                ],
            ],
        ];

        $batch = $glentryMgr->GetList($params);
        $batch = array_unique($batch);


        $ok = $ok && $this->checkOpenBooks($batch[0]['ENTRY_DATE'], $batch[0]['LOCATION#'], 'delete');


        if (count($batch) > 1)
        {
            $gErr = Globals::$g->gErr;
            $msg = 'records to adjust not from the same parent record  $existingGLEntry1, $existingGLEntry2 !';
            $gErr->addIAError(
                'INV-0314',
                __FILE__ . ':' . __LINE__,
                $msg, ['EXISTINGGLENTRY1' => $existingGLEntry1, 'EXISTINGGLENTRY2' => $existingGLEntry2]
            );
            $ok = $ok && false;
        }

        $batchID = $batch[0]['BATCHNO'];
        if (!isset($batchID))
        {
            $gErr = Globals::$g->gErr;
            $msg = 'Could not find GL record $batchID!';
            $gErr->addIAError('INV-0315', __FILE__ . ':' . __LINE__, $msg, ['BATCHID' => $batchID]);
            $ok = $ok && false;
        }

        // all setup, delete the entry
        $ok = $ok && $glbatchMgr->delete($batchID, true);

        $ok = $ok && $this->commitTrx($source);
        if (!$ok)
        {
//            if (!HasWarnings() || HasErrors())
//            {
//                $gErr = Globals::$g->gErr;
//                $msg = _('Could not delete the COGS adjustment!');
//                $gErr->addError('BL03002068', __FILE__ . ':' . __LINE__, $msg);
//            }
            $this->rollbackTrx($source);
        }

        return $ok;
    }


    /**
     * @param string $postingDate
     * @param float $amountToPost
     * @param float $trx_amountToPost
     * @param int $existingGLEntry1
     * @param int $existingGLEntry2
     * @param int $docEntryRecordNo
     * @param string $manualResolve
     * @return bool
     */
    function postCogsGLEntry($postingDate, $amountToPost, $trx_amountToPost, $existingGLEntry1, $existingGLEntry2, $docEntryRecordNo, $manualResolve)
    {
        $ok = true;
        $gErr = Globals::$g->gErr;
        $pol = 'inv/lists/cogsclosedje/create';
        if (!CheckAuthorization(GetOperationId($pol), 1))
        {
            $msg = "No adjustments were posted because you don’t have the appropriate permission.<br> Ask your system administrator for assistance.";
            $gErr->addIAError('INV-0661', __FILE__ . ':' . __LINE__, $msg, []);
            $this->commitStatus['MESSAGE'][] = $msg;
            return false;
        }

        $params = [
            'BATCH_DATE'          => $postingDate,
            'AMOUNT'              => $amountToPost,
            'TRX_AMOUNT'          => $trx_amountToPost,
            'EXISTINGENTRY1'      => $existingGLEntry1,
            'EXISTINGENTRY2'      => $existingGLEntry2,
            'DOCENTRY'            => $docEntryRecordNo,
            'CLOSEDPERIODJOURNAL' => GetPreferenceForProperty(Globals::$g->kINVid, 'CLOSEDPERIODJOURNAL'),
        ];

        global $gManagerFactory;
        // checked the journal from the perfs
        $gljournalEntryMgr = $gManagerFactory->getManager('gljournal');
        $journal = $gljournalEntryMgr->GetRecordNoFromVid($params["CLOSEDPERIODJOURNAL"]);
        if (!isset($journal))
        {
            $closejournal = $params['CLOSEDPERIODJOURNAL'];
            if (empty($closejournal))
            {
                $msg = "Value for closed period journal preference is not set.";
                $errorCode = 'INV-0316';
                $placeHolder = [];
            }
            else
            {
                $msg = "Value for closed period journal preference ($closejournal) is not a valid. ";
                $errorCode = 'INV-0317';
                $placeHolder = ['CLOSEJOURNAL' => $closejournal];
            }
            $gErr->addIAError($errorCode, __FILE__ . ':' . __LINE__, $msg, $placeHolder);
            $ok = $ok && false;
        }

        /** @var GLBatchManager $glbatchMgr */
        $glbatchMgr = $gManagerFactory->getManager('glbatch');
        $glbatchEntryMgr = $gManagerFactory->getManager('glentry');

        $params['EXISTINGENTRY'][] = $glbatchEntryMgr->get($existingGLEntry1);
        $params['EXISTINGENTRY'][] = $glbatchEntryMgr->get($existingGLEntry2);

        $batchID1 = $params['EXISTINGENTRY']['0']['BATCHNO'];
        $batchID2 = $params['EXISTINGENTRY']['1']['BATCHNO'];

        if ($batchID1 != $batchID2)
        {
            $gErr = Globals::$g->gErr;
            $msg = 'records to adjust not from the same parent record  $existingGLEntry1, $existingGLEntry2 !';
            $gErr->addIAError(
                'INV-0662',
                __FILE__ . ':' . __LINE__,
                $msg, ['EXISTINGGLENTRY1' => $existingGLEntry1, 'EXISTINGGLENTRY2' => $existingGLEntry2]
            );
            $ok = $ok && false;
        }

        // parent record
        $record = $batchID1;
        // entry line number
        $params['LINECOUNT'] = 1;

        if ($ok)
        {
            // get current gl value
            $glbatchrecord = $glbatchMgr->Get($record);
            if (!isset($glbatchrecord))
            {
                $gErr = Globals::$g->gErr;
                $msg = 'Could not find GL record  $record  !';
                $gErr->addIAError('INV-0318', __FILE__ . ':' . __LINE__, $msg, ['RECORD' => $record]);
                $ok = $ok && false;
            }
        }

        if ($ok)
        {
            //update header
            $newGladjrecord = $this->createheader($glbatchrecord, $params);
            $postingrec = $docEntryRecordNo;
            $postingID = (int)microtime(true);  // not 100% foolproof, but should make it so often only ONE of these pairs of writes has ONE 'postingID'.
            // create posting id
            $newGladjrecord['POSTINGID'] = $postingID;
            $newGladjrecord['REFERENCENO'] = $postingrec . '--' . $postingID;

            $newGladjrecord['REFERENCENO'] = 'COGS ADJ  - ' . ServeCurrentTimestamp();

            // update changed fields in gl record
            for ($count = 0; $count < 2; $count++)
            {
                // update line item
                $line = $this->createline($params['EXISTINGENTRY'][$count], $params);
                $newGladjrecord['ENTRIES'][] = $line;
            }

            $gManagerFactory = Globals::$g->gManagerFactory;
            /** @var GLBatchManager $glbatchMgr */
            $glbatchMgr = $gManagerFactory->getManager('GLBatch');

            if (!($manualResolve))
            {
                // all setup, add the entry
                $ok = $ok && $glbatchMgr->add($newGladjrecord);
            }
            if ($ok)
            {
                // return the gl record
                $this->Gladjrecord = $newGladjrecord;
            }

        }

        return $ok;
    }


    /**
     * @param string $extPath
     * @param mixed $extValue
     * @param mixed $info
     * @param bool $doFieldTypeFunction
     * @param bool $addErr
     * @return mixed|string
     */

    function _TransformExternalValue($extPath, $extValue, $info = null, $doFieldTypeFunction = true, $addErr = true)

    {
        switch (strtolower($extPath) )
        {
            case 'deglresolve.cost_adj_needed':
            case 'cogsresolve.manual_adjustment':
            case 'needsadjustment':
                // fix value
                $retval = $extValue;
                $retval = $retval == 'true' ? 'T' : $retval;
                $retval = $retval == 'TRUE' ? 'T' : $retval;
                $retval = $retval == 'false' ? 'F' : $retval;
                $retval = $retval == 'FALSE' ? 'F' : $retval;
                $retval = $retval == 't' ? 'T' : $retval;
                $retval = $retval == 'f' ? 'F' : $retval;
                break;

            default:
                $retval = parent::_TransformExternalValue($extPath, $extValue, $info, $doFieldTypeFunction, $addErr);
                break;

        }


        return $retval;
    }

    /**
     * @param   string $date
     * @param string $locationkey
     * @param  string $action
     *
     * @return bool
     */
    function checkOpenBooks($date, $locationkey, $action)
    {
        $ok = true;
        if ($locationkey && IsMultiEntityCompany())
        {
            $opendate = GetCompanyOpenDate(true, $locationkey);
        }
        else
        {
            $opendate = GetCompanyOpenDate();
        }
        $closeBooksError = '';
        $correction = '';
        if ($action == 'post')
        {
            $closeBooksError = 'Adjustments to the general ledger can only be posted in open periods. ';
            $correction =
                "<BR>" .
                'Reselect the adjustments to post, and, in the Post Adjustments dialog, enter a GL posting date that is in an open period.'
                . "<BR>" .
                '(In multi-entity organizations, different entities might have different dates for their currently open periods.)';
            $errorCode = 'INV-0468';
        }
        elseif ($action == 'delete')
        {
            $closeBooksError = 'Adjustments with a date that is in a closed period can’t be deleted from the general ledger. ';
            $correction =
                "<BR>" .
                'To delete a posted adjustment, select only those adjustments where the adjustment date is in an open period. '
                . "<BR>" .
                '(In multi-entity organizations, different entities might have different dates for their currently open periods.) ';
            $errorCode = 'INV-0469';
        }

        if (SysDateCompare($date, $opendate) < 0)
        {
            $ok = false;
            Globals::$g->gErr->addIAError(
                $errorCode, __FILE__ . ':' . __LINE__,
                $closeBooksError . $correction, []
            );
        }

        return $ok;
    }


    /**
     * Similar to GetList, but operates on an unstructured where clause.  Returns full objects
     *   UNLESS the given maxNumber is exceeded - then it returns an array containing the key fields.
     *
     * @param string   $query        String the where clause
     * @param int      $maxNumber
     * @param bool     &$outKeysOnly (output) returned true if maxNumber exceeded and keys only returned
     * @param string[] $fields
     *
     * @return array list of objects matching the query
     */
    function getByQuery($query, $maxNumber, &$outKeysOnly, $fields = null)
    {

        $pattern = '/(?i)(NEEDSADJUSTMENT)\s*(\S)\s*\'(\w*)\'/';
        $matches = [];

        preg_match($pattern, $query, $matches);
        // save the needs adjustment value for later
        // used in getlist
        $this->needsadjustment = $matches;
        $values = parent::getByQuery($query, $maxNumber, $keysOnly, $fields);

        return $values;
    }


}

