<?php
import('editor');
require_once 'backend_dates.inc';
require_once 'scm_util.inc';
require_once 'MailaddressManager.cls';
require_once 'Util_DataRecordFormatter.cls';

class DocumentEditor extends Editor
{

    // private variables
    /**
     * @var bool $_noConvertLink
     */
    var $_noConvertLink; //If set, do not display the convert link

    /**
     * @var bool $_deptOverride
     *          override dept and loc based on template configuration
     */
    var $_deptOverride;

    /**
     * @var bool $_locOverride
     */
    var $_locOverride;

    /**
     * @var bool $_fromError
     */
    var $_fromError;

    /**
     * @var bool $_docIsOwned
     */
    var $_docIsOwned;

    /**
     * @var bool $_ismcpEnabled
     */
    var $_ismcpEnabled;

    /**
     * @var bool $atlas
     */
    var $atlas;

    /**
     * @var bool $showDraft
     */
    var $showDraft = false;

    /**
     * @var bool $isAdvancedSetup
     */
    var $isAdvancedSetup = false;

    /**
     * @var array $printTemplateCache
     */
    var $printTemplateCache = array();

    /**
     * @var  array[][] $cust_dim_cache
     */
    var $cust_dim_cache;

    /**
     * @var array $pt_relationships
     */
    var $pt_relationships;

    /**
     * @var null|string $currentMultilinePath
     */
    private static $currentMultilinePath;

    /**
     * @var string $sfcrlimit
     */
    var $sfcrlimit = "";

    /**
     * @var string $sftotdue
     */
    var $sftotdue;

    /**
     * @var bool $_doctypeeditable
     */
    var $_doctypeeditable;

    /**
     * @var bool $_stateEditable
     */
    var $_stateEditable;

    /**
     * @var bool $priceFetchDisabled
     */
    var $priceFetchDisabled;

    /**
     * @var string $autoBatchFrequency
     */
    var $autoBatchFrequency;

    /**
     * @var array $tempfields
     */
    var $tempfields;

    /**
     * @var bool $itemsHaveStartEndDate
     */
    var $itemsHaveStartEndDate;

    /**
     * @var array $xsltemplateInfo
     */
    var $xsltemplateInfo;

    /**
     * @var string $XSL_Template_Type
     */
    var $XSL_Template_Type;

    /**
     * @var string $sfdcPricing
     */
    var $sfdcPricing;   // a string that contains 'true' or 'false' (or is empty, meaning 'false')


    /**
     *
     */
    function InitConstants()
    {
        Editor::InitConstants();
        $this->kActionHandlers[$this->kDeriveDocumentAction] =
            array(
                'handler' => 'ProcessDeriveDocumentAction',
                'states'  => array(
                    $this->kShowNewState,
                    $this->kShowEditState,
                    $this->kShowViewState
                )
            );
        $this->kActionHandlers[$this->kFetchForNewAction] =
            array('handler' => 'ProcessEditNewAction',
                  'states'  => array($this->kInitState,
                      $this->kShowNewState));

        $this->kActionHandlers[$this->kFetchForEditAction] =
            array('handler' => 'ProcessEditAction',
                  'states'  => array($this->kInitState,
                      $this->kShowViewState,
                      $this->kShowEditState));
        $this->kActionHandlers['fetchdefaultrevrectemplate'] = array(
            'handler' => 'FetchDefaultRevRecTemplate',
            'states'  => array($this->kInitState)
        );

        $this->kActionHandlers['createsubmit'] =
            array(
                'handler' => 'ProcessCreateSubmitAction',
                'states'  => array(
                    $this->kShowNewState,
                    $this->kShowEditState,
                    $this->kCreateWarningState,
                    $this->kEditWarningState
                ),
                'csrf'    => true,
            );

        $this->kActionHandlers['editsubmit'] =
            array(
                'handler' => 'ProcessEditSubmitAction',
                'states'  => array(
                    $this->kShowNewState,
                    $this->kShowEditState,
                    $this->kCreateWarningState,
                    $this->kEditWarningState
                ),
                'csrf'    => true,
            );

        $this->DocumentInitConstants();
    }


    /**
     * @var string $mod
     */
    var $mod = "";

    /**
     * @var string $dt
     */
    var $dt = "";

    /**
     * @var string $do
     */
    var $do = "";

    /**
     * @var int $cny
     */
    var $cny = 0;

    /**
     * @var string $docpar
     */
    var $docpar = '';

    /**
     * @return string
     */
    protected function getDocType()
    {
        return $this->dt;
    }

    /**
     * @return null|string
     */
    function getRequestModule()
    {
        $mod = Request::$r->_mod;
        if ($mod == "pa") {
            $mod = "so";
        }
        return $mod;
    }


    /**
     *
     */
    function DocumentInitConstants()
    {

        $this->mod = $this->getRequestModule();
        $this->dt = Request::$r->_dt;
        $this->do = Request::$r->_do;
        $this->_ismcpEnabled = IsMCPEnabled($this->mod);
        $this->cny = GetMyCompany();
        $this->atlas = IsMCMESubscribed();

        // When comming from Map doctype will NOT be set, pick the first doctype for the app
        if (!$this->dt && $this->do == 'create') {
            $this->_doctypeeditable = true;

            $cat = Request::$r->_cat;

            import('DocumentManager');
            $docs = GetDocumentParams($this->mod, $cat, true);

            if (count($docs) > 0) {
                $this->dt = $docs[0];

                if (isset($this->dt) && $this->dt != '') {
                    Request::$r->_dt = $this->dt;
                }
            }
        }
    }


    /**
     * @param bool $getLatest
     *
     *
     * @return array
     */
    function GetBaseDocPar($getLatest = false)
    {
        if (!$this->dt || $this->dt == '') {
            $this->dt = Request::$r->_dt;
        }
        if ($this->dt && (!isset($this->docpar) || $this->docpar == '')) {
            /** @var DocumentParamsManager $docparMgr */
            $docparMgr = Globals::$g->gManagerFactory->getManager($this->mod . 'documentparams');
            $this->docpar = $docparMgr->GetBaseLatest($this->dt, $getLatest);
        }
        return $this->docpar;
    }


    /**
     * @return mixed
     */
    function &GetTemplate()
    {
        // Go Back button must pass document type value
        global $gGoBackParams;
        $copy = Request::$r->_copymode;
        $gGoBackParams['.dt'] = $this->dt;
        $gGoBackParams['.copymode'] = $copy;
        return parent::GetTemplate();
    }


    /**
     *
     */
    function ShowPreListerEditorInfo()
    {
        // Does nothing allow to override
        $msg = $this->GetMessage();
        if (!$msg) {
            $msg = Request::$r->_msg;
        }
        if ($msg) {
            ?>
            <center>
                <table border="0" cellpadding="1" cellspacing="0" width="70%" bgcolor="#999966">
                    <tr>
                        <td valign="top">

                            <table border="0" cellpadding="4" cellspacing="0" width="100%" bgcolor="#FFFFCC">
                                <tr>
                                    <td valign="middle" align="center">
                                        <font face="Verdana, Arial, Helvetica" size="2"><b><? echo $msg; ?></b></font>
                                    </td>
                                </tr>
                            </table>

                        </td>
                    </tr>
                </table>
            </center>
            <?
            $this->message = '';
        }
    }


    /**
     * @param string   $_msg
     * @param array|null  $obj
     */
    function SetMessageWithObject($_msg, $obj)
    {
        if ($obj && $obj['DOCID']) {

            $this->message = "Your Document '" . $obj['DOCID'] . "' has been Created";
            if (isl_strstr($this->done, "lister")) {
                $outputstr = '';
                $parms = explode('&', $this->done);
                $msgset = false;
                $qryset = false;
                $dtset = false;
                foreach ($parms as $parm) {

                    if (isl_substr($parm, 0, 4) == '_msg') {
                        $parm = '_msg=' . urlencode($this->message);
                        $msgset = true;
                    }
                    if (isl_substr($parm, 0, 13) == '.queryfromend') {
                        $parm = '.queryfromend=1';
                        $qryset = true;
                    }
                    if (isl_substr($parm, 0, 3) == '.dt') {
                        $parm = '.dt=' . urlencode($obj['DOCPARID']);
                        $dtset = true;
                    }
                    $outputstr .= $parm . '&';
                }

                if ( $msgset != true) {
                    $outputstr .= '_msg=' . urlencode($this->message) . '&';
                }
                if ( $qryset != true) {
                    $outputstr .= '.queryfromend=1&';
                }
                if ( $dtset != true) {
                    $outputstr .= '.dt=' . urlencode($obj['DOCPARID']) . '&';
                }

                $this->done = $outputstr;
            }
        } else {
            $this->SetMessage($_msg);
        }
    }

    /**
     * @param string[] $_params
     */
    function ProcessCreateSubmitAction(&$_params)
    {
        $obj =& Request::$r->GetCurrentObject();
        $obj['_issubmit'] = 'true';

        $this->ProcessDraftCreateAction($_params);
    }

    /**
     * @param string[] $_params
     */
    function ProcessEditSubmitAction(&$_params)
    {
        $obj =& Request::$r->GetCurrentObject();
        $obj['_issubmit'] = 'true';

        foreach ( $obj['ENTRIES'] as $key => $lineEntry) {
            if (!isset($obj['ENTRIES'][$key]['ITEMDESC'])) {
                $obj['ENTRIES'][$key]['ITEMDESC'] = '';
            }
        }

        $this->ProcessDraftSaveAction($_params);
    }


    /**
     * Hook for subclasses to prepare the object during a create action
     * At the time of the call the object is in business form
     *
     * @param array &$obj  the object (in and out)
     *
     * @return bool
     */
    protected function prepareObjectForCreate(&$obj)
    {
        foreach ( $obj['ENTRIES'] as $key => $lineEntry) {
            if (!isset($obj['ENTRIES'][$key]['ITEMDESC'])) {
                $obj['ENTRIES'][$key]['ITEMDESC'] = '';
            }
        }

        return true;
    }

    /**
     * Hook for subclasses to prepare the object during a save action
     * At the time of the call the object is in business form
     *
     * @param array $obj  the object (in and out)
     *
     * @return bool
     */
    protected function prepareObjectForSave(&$obj)
    {
        foreach ( $obj['ENTRIES'] as $key => $lineEntry) {
            if (!isset($obj['ENTRIES'][$key]['ITEMDESC'])) {
                $obj['ENTRIES'][$key]['ITEMDESC'] = '';
            }
        }

        return true;
    }

    /**
     * @param array $_params
     *
     * @return bool
     */
    function ProcessCreateAction(&$_params)
    {
        /**
         * @var URLS $gURLs
         */
        global $gURLs;

        $_sess = Session::getKey();

        $entityMgr = $this->GetManager($_params['entity']);

        $obj =& Request::$r->GetCurrentObject();
        $obj = $this->DoRefreshAction($_params, $obj);

        $ok = $this->PrepareInputValues($_params, $obj);
        $temp_obj = $obj;
        $this->EditorGetSubTotals($_params, $temp_obj, true);
        $entityMgr->setWarningValidation();

        // Setting the request objects as part of the $obj array that would be used by the Add/Set of the Managers
        $obj['_kNoWarn'] = Request::$r->_kNoWarn;
        $obj['_kNoDupl'] = Request::$r->_kNoDupl;
        $obj['_do'] = Request::$r->_do;
        $obj['_mod'] = Request::$r->_mod;

        $ok = $ok && $this->prepareObjectForCreate($obj);
        $ok = $ok && $this->validatePlatformData($obj);

        $ok = $ok && $entityMgr->add($obj);
        $entityDesc = ($_params['entityDesc']) ?: "record";

        if (!$ok) {
            $obj = $temp_obj;

            $gErr = Globals::$g->gErr;
            if ($gErr->hasWarnings()) {
                $this->warningmessage = true;
                $this->state = $this->kCreateWarningState;
                if (!util_isPlatformDisabled()) {
                    $entityMgr->getRelationships($obj, false, false, false, true);
                    $this->setPlatformData($obj);
                }
            }

            $warnmessage = HasErrors();
            if ($warnmessage) {
                $gErr->addError(
                    "BL03000021", __FILE__ . ":" . __LINE__,
                    _("Creating $entityDesc failed")
                );
                $this->state = $this->kErrorState;
            } else {
                $obj =& Request::$r->GetCurrentObject();
                Request::$r->SetCurrentObject($obj);
                Request::$r->_action = $this->kCreateAction;
                $this->state = $this->kShowNewState;
            }
        } else {
            $confirmation = _("The $entityDesc was created successfully");
            $this->SetMessageWithObject($confirmation, $obj);

            //if (strcmp($this->GetPreference($_params, "Create.WhatToDoAfter"),"Create") == 0)
            $after = Request::$r->after;

            if ($after == 1) {
                Request::$r->_currentlayer = '';
                Request::$r->_changed = 'false';
                $obj =& Request::$r->GetCurrentObject();
                EntityManager::SetByPath($obj, $entityMgr->GetKeyFieldName(), '');

                $ent = $obj['CUSTVENDID'];
                [$ent] = explode('--', $ent);

                $op = $_params['documentcreateop'];

                if ($this->state != $this->kErrorState) {
                    Request::$r->SetCurrentObject($obj);
                    $this->state = $this->kShowNewState;

                    Fwd('editor.phtml?.sess=' . $_sess . '&.op=' . $op . '&_ent=' . urlencode($ent) . '&.dt=' . urlencode($this->dt) . '&_msg=' . urlencode($this->GetMessage()), $this->done);
                }
            } elseif ($this->GetPreference($_params, "Create.RequireConfirmation")) {
                $this->state = $this->kConfirmState;
            } elseif ($gURLs->HasReturnPath()) {
                $this->state = $this->kGoBackState;
            } elseif ($_params['popup']) {
                $this->state = $this->kCloseState;
            } else {
                $this->state = $this->kGoHomeState;
            }
        }

        $list_op = GetOperationId($this->mod . '/lists/' . $this->mod . 'document');
        $_done = Request::$r->_done;
        if (isl_strstr($_done, "sforcekey") === false) {
            $this->done = 'lister.phtml?.op=' . $list_op . '&.dt=' . urlencode($this->dt) . '&.sess=' . $_sess;
        }
        return true;
    }


    /**
     * @param array $_params
     */
    function ProcessDeriveDocumentAction(/** @noinspection PhpUnusedParameterInspection */ &$_params)
    {
        $_sess = Session::getKey();

        $obj =& Request::$r->GetCurrentObject();

        $done = Request::$r->_done;
        $ent = $obj['CUSTVENDID'];
        [$ent] = explode('--', $ent);

        $srcdoc = $obj['DOCID'];
        $dt = $obj['DERIVEDOCTYPE'];
        $op = GetOperationId($this->mod . '/activities/' . $this->mod . 'document/create');
        $url = "editor.phtml?.sess=$_sess&.op=$op&.do=create&_dt=" . urlencode($dt) . "&_ent=" . urlencode($ent) . "&_mod=$this->mod&_srcdoc=" . urlencode($srcdoc) . "&_copymode=Update&_derive=1";
        Fwd($url, $done);

    }

    /**
     * @param string $entity
     * @param string $objId
     *
     * @return array
     */
    protected function getEntityData($entity, $objId)
    {
        $obj = parent::getEntityData($entity, $objId);

        $multipleSrcDocText = ConversionManager::getmultipleSourceDocsText();
        if ($obj['CREATEDFROM'] != $multipleSrcDocText && isset($obj['HISTORY'])) {
            foreach ($obj['HISTORY'] as $idx => $row) {
                $obj['HISTORY'][$idx]['DOCUMENTMODIFIED'] = FormatTimestampForDisplay(
                    GMTToUserTZ(FormatTimestampForStorage($row['DOCUMENTMODIFIED']))
                );
            }
        }

        return $obj;
    }

    /**
     * @param array $_params
     */
    function ProcessViewAction(&$_params)
    {
        $objId = Request::$r->{Globals::$g->kId};
        $obj = $this->getEntityData($_params['entity'], $objId);

        $this->EditorGetSubTotals($_params, $obj, false);

        if (!$obj || !isset($obj['RECORDNO'])) {
            $entityDesc = $_params['entityDesc'];
            global $gErr;
            $gErr->addError("BL03000021", __FILE__ . ":" . __LINE__, _("Cannot access $entityDesc '$objId'."));
            $this->state = $this->kErrorState;
        } else {
            $this->PreprocessViewAction($obj);
            Request::$r->SetCurrentObject($obj);
            $this->state = $this->kShowViewState;
        }
    }


    /**
     * @param array $obj
     *
     * @throws Exception
     */
    function PreprocessViewAction(&$obj)
    {
        global $gManagerFactory;
        global $kSOid, $kPOid, $kINVid;

        $itemMgr = $gManagerFactory->getManager('item');

        $modArray = array('so' => $kSOid, 'po' => $kPOid, 'inv' => $kINVid);
        $precisionFields = array('so' => 'NUMDEC_SALE', 'po' => 'NUMDEC_PUR', 'inv' => 'NUMDEC_STD');

        GetModulePreferences($modArray[$this->mod], $prefs);
        $appPrecision = ($prefs['ITEMPRECISION']) ?: 2;


        $itemsArr = array();
        foreach ( $obj['ENTRIES'] as $entry) {
            [$itemid] = explode('--', $entry['ITEMID']);
            $itemsArr[] = $itemid;
        }

        //$uomInfoCache = $itemMgr->GetUOMPrecissionInfo($itemsArr);
        $itemidAsKey = true;
        $uomInfoVals = $itemMgr->GetUOMInfoCache($itemsArr, $itemidAsKey);

        // SRAO:: UOM Changes doen here needs testing.
        foreach ($obj['ENTRIES'] as $key => $entry) {
            $itemMgr->GetLineEntry_UOMPrecissionInfo($entry, $uomInfoVals, $conversion, $uomPrecission);
            //$conversion 	= $uomInfoVals[$entry['UNIT']]['CONVFACTOR'];
            //$uomPrecission 	= $uomInfoVals[$entry['UNIT']]['NUMDEC'];
            $obj['ENTRIES'][$key]['QTY_CONVERTED'] = ibcdiv($entry['QTY_CONVERTED'], $conversion, $uomPrecission, true);


            if ($entry['ITEM'][$precisionFields[$this->mod]] != '') {
                $itemPrecision = $entry['ITEM'][$precisionFields[$this->mod]];
            } else {
                $itemPrecision = $appPrecision;
            }
            $obj['ENTRIES'][$key]['RETAILPRICE'] = ibcmul($obj['ENTRIES'][$key]['RETAILPRICE'], $conversion, $itemPrecision, false);
            $obj['ENTRIES'][$key]['UIPRICE'] = ibcmul($obj['ENTRIES'][$key]['UIPRICE'], '1', $itemPrecision, true);

            //setting up UIPrice as if the value is 0, it does not respect the itemprecision.

            if ($obj['ENTRIES'][$key]['UIPRICE'] == 0) {

                $obj['ENTRIES'][$key]['UIPRICE'] = "0." . str_repeat("0", $itemPrecision);

            }

            $obj['ENTRIES'][$key]['UIVALUE'] = ibcmul($obj['ENTRIES'][$key]['UIVALUE'], '1', 2, true);

            $obj['ENTRIES'][$key]['TRX_PRICE'] = ibcmul($obj['ENTRIES'][$key]['TRX_PRICE'], '1', $itemPrecision, false);

            if (isset($obj['ENTRIES'][$key]['WAREHOUSE']['LOCATION_NO'])) {
                if (isset($obj['ENTRIES'][$key]['WAREHOUSE']['NAME'])) {
                    $obj['ENTRIES'][$key]['WAREHOUSE']['LOCATION_NO'] = $obj['ENTRIES'][$key]['WAREHOUSE']['LOCATION_NO'] . '--' . $obj['ENTRIES'][$key]['WAREHOUSE']['NAME'];

                }
            }
        }


        if (!$obj) {
            /** @noinspection PhpUndefinedVariableInspection */
            $entityDesc = $_params['entityDesc'];
            global $gErr;
            /** @noinspection PhpUndefinedVariableInspection */
            $gErr->addError("BL03000021", __FILE__ . ":" . __LINE__, _("Fetching $entityDesc '$objId' failed"));
            $this->state = $this->kErrorState;
        } else {
            Request::$r->SetCurrentObject($obj);
            $this->state = $this->kShowViewState;
        }
    }

    /**
     * @param array         $values
     * @param EntityManager $srcEntityMgr
     *
     * @return mixed
     * @throws Exception
     *
     * This function is used when a document is created from Multiple source transactions (mass comversion)
     * This function gets all the source document entries and filters the fully converted entries
     * This function is called from ProcessEditNewAction
     * $values -> this is the temp object stored in object_store table
     * $srcEntityMgr -> the source entity manager object
     */
    function ProcessMultipleSourceTransactions($values, $srcEntityMgr)
    {
        global $gManagerFactory;
        $itemMgr = $gManagerFactory->getManager('item');
        $destdoctype = Request::$r->_dt;

        $docparMgr = $gManagerFactory->getManager('documentparams');

        $newdocpar = $docparMgr->GetBaseLatest($destdoctype);
        $newenableoverride = $newdocpar['ENABLEOVERRIDETAX'];

        // get all the convertable line entries from each source document
        $sourceDocs = $values['SOURCE_DOCS'];
        $sDocs = array();
        foreach ( $sourceDocs as $sourceDocID) {
            $sourceDoc = $srcEntityMgr->get($sourceDocID);
            $sDocs[] = "['" . addslashes($sourceDocID) . "']";

            foreach ( $sourceDoc['ENTRIES'] as $sourceEntry) {
                $itemid = explode('--', $sourceEntry['ITEMID']);//splitting the itemid
                $itemid = $itemid[0];

                if (isset($sourceEntry['WAREHOUSE']['LOCATION_NO'])) {
                    if (isset($sourceEntry['WAREHOUSE']['NAME'])) {
                        $sourceEntry['WAREHOUSE']['LOCATION_NO'] = $sourceEntry['WAREHOUSE']['LOCATION_NO'] . '--' . $sourceEntry['WAREHOUSE']['NAME'];
                    }
                }

                /*
                $uomInfo = $itemMgr->GetUOMInfo($itemid);
                $conversion=1;
                if ($sourceEntry['UNIT'] != $uomInfo['STD_UNIT']) {
                if ($sourceEntry['UNIT'] == $uomInfo['PUR_UNIT']) {
                $conversion	= $uomInfo['PUNIT_FACTOR'];
                $uomPrecission = $uomInfo['PUR_DEC'];
                } elseif ($sourceEntry['UNIT'] == $uomInfo['SAL_UNIT']) {
                $conversion	= $uomInfo['SUNIT_FACTOR'];
                $uomPrecission = $uomInfo['SAL_DEC'];
                }
                }else{
                $uomPrecission = $uomInfo['STD_DEC'];
                }
                */

                // Get the conversion factor
                $uomInfo = $itemMgr->GetUOMInfoCache(array($itemid), true);
                $conversion = $uomInfo[$sourceEntry['UNIT']]['CONVFACTOR'] ?: 1;
                $uomPrecission = $uomInfo[$sourceEntry['UNIT']]['NUMDEC'];
                $uom_is_base = $uomInfo[$sourceEntry['UNIT']]['ISBASE'];

                $uomPrecission = ($uomPrecission > 0 && $uom_is_base != 'T') ? $uomPrecission : 4;

                // pick only those entries which are not fully converted
                if ($sourceEntry['QUANTITY'] != $sourceEntry['QTY_CONVERTED']) {

                    // get the remaining quantity to convert
                    $sourceEntry['QUANTITY'] = ibcsub($sourceEntry['QUANTITY'], $sourceEntry['QTY_CONVERTED'], $uomPrecission, true);
                    $sourceEntry['UIQTY'] = ibcdiv($sourceEntry['QUANTITY'], $conversion, $uomPrecission, true);

                    // get the source docid & linekey
                    $sourceEntry['SOURCE_DOCKEY'] = $sourceEntry['DOCHDRNO'];
                    $sourceEntry['SOURCE_DOCLINEKEY'] = $sourceEntry['RECORDNO'];
                    $sourceEntry['SOURCE_DOCID'] = $sourceDoc['DOCID'];

                    // If destination document has subscribed to override tax
                    // then "Override Tax" tax checkbox value should be defaulted to ITEM.TAXABLE value
                    if ($newenableoverride == 'true') {
                        $sourceEntry['OVERRIDETAX'] = $sourceEntry['ITEM']['TAXABLE'];
                    }
                    unset($sourceEntry['RECORDNO']);
                    $values['ENTRIES'][] = $sourceEntry;
                }
            }

            // get source docuemnts history
            foreach ($sourceDoc['HISTORY'] as $shistory) {
                if ($shistory['DOCUMENTID'] == $sourceDocID) {
                    $values['HISTORY'][] = $shistory;
                }
            }
        }

        // JS array sourceDocsArr is also defined in ShowScripts in edit mode if the child document is created from multiple source transactions
        // the following sourceDocsArr var is defined only when creating a new transaction from multiple source docuemnts
        $sourceDocsjs = '[' . implode(',', $sDocs) . ']';
        $sourceDocsjs = "<SCRIPT> sourceDocsArr = " . $sourceDocsjs . "; </SCRIPT>";
        echo $sourceDocsjs;

        return $values;
    }


    /**
     * @param array $_params
     *
     * @return bool
     * @throws Exception
     */
    function ProcessEditNewAction(&$_params)
    {
        global $gManagerFactory;

        $copy = Request::$r->_copymode;
        $_createdfrom = Request::$r->_createdfrom;
        $this->state = 'shownew';

        if ($this->_fromError) {
            return true;
        }

        $destdoctype = Request::$r->_dt;
        $recalledID = Request::$r->{Globals::$g->kId};

        // Copy compatible custom fields from source document to destination document
        $srcdoctype = GetDocumentType($recalledID);

        $srcEntityMgr = $gManagerFactory->getManager($_params['entity'], true, array( 'DOCTYPE' => $srcdoctype));
        $destEntityMgr = $gManagerFactory->getManager($_params['entity'], true, array( 'DOCTYPE' => $destdoctype));

        /** @noinspection PhpUndefinedVariableInspection */
        if ($this->ProcessErrorRetrivalAction($entityMgr)) {
            $this->state = $this->kShowNewState;
            return true;
        }
        Request::$r->_changed = false;

        // There is a weird mix of recalled doc data and default doc data here.  If there are problems,
        // look here.
        $multipleSrcDocText = ConversionManager::getmultipleSourceDocsText();
        if ($_createdfrom == $multipleSrcDocText && $copy == 'Update') {
            $objStoreId = Request::$r->_objstoreid;
            /** @var ObjectStoreManager $objectStore */
            $objectStore = $gManagerFactory->getManager('objectstore');
            $objs = $objectStore->Get($objStoreId);
            if (isset($objs['OBJECTDATA'])) {
                $new = $this->ProcessMultipleSourceTransactions($objs['OBJECTDATA'], $srcEntityMgr);
            }

        } elseif ($recalledID) {
            $old = $srcEntityMgr->get($recalledID);
            if (!$old) {
                global $gErr;
                $gErr->addError(
                    "BL03000021", __FILE__ . ":" . __LINE__,
                    _(
                        "Fetching transaction '$recalledID' failed. " .
                        "TransactionID '$recalledID' has been defined in the setup as a template for creating new transactions."
                    )
                );
                $this->state = $this->kErrorState;
            } else {
                $this->processCopyConvert($copy, $old);
                if (!util_isPlatformDisabled()) {
                    $srcEntityMgr->getRelationships($old, false, false, false, true);
                }
                // recalculate subtotals based on new definition.

                $docpar = $this->GetBaseDocPar();

                $itemsArr = array();
                for ($i = 0; $i < count($old['ENTRIES']); $i++) {
                    if (isset($old['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO'])) {
                        if (isset($old['ENTRIES'][$i]['WAREHOUSE']['NAME'])) {
                            $old['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO'] = $old['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO'] . '--' . $old['ENTRIES'][$i]['WAREHOUSE']['NAME'];
                        }
                    }

                    [$itemid] = explode('--', $old['ENTRIES'][$i]['ITEMID']);
                    $itemsArr[] = $itemid;
                }

                $new = $old;
                if (!util_isPlatformDisabled()) {
                    $this->setPlatformData($new);
                }

                // when converting
                if ($copy == 'Update') {
                    unset($new['ENTRIES']);

                    $itemMgr = $gManagerFactory->getManager('item');
                    //$uomInfoCache = $itemMgr->GetUOMPrecissionInfo($itemsArr);
                    $itemidAsKey = true;
                    $uomInfoVals = $itemMgr->GetUOMInfoCache($itemsArr, $itemidAsKey);

                    foreach ( $old['ENTRIES'] as $oldEntry) {
                        // pick only those entries which are not fully converted
                        if ($oldEntry['QUANTITY'] != $oldEntry['QTY_CONVERTED']) {
                            $itemMgr->GetLineEntry_UOMPrecissionInfo($oldEntry, $uomInfoVals, $conversion, $uomPrecission);
                            // get the remaining quantity to convert
                            $oldEntry['QUANTITY'] = ibcsub($oldEntry['QUANTITY'], $oldEntry['QTY_CONVERTED'], $uomPrecission, true);
                            $oldEntry['UIQTY'] = ibcdiv($oldEntry['QUANTITY'], $conversion, $uomPrecission, true);

                            // get the source docid & linekey
                            $oldEntry['SOURCE_DOCKEY'] = $oldEntry['DOCHDRNO'];
                            $oldEntry['SOURCE_DOCLINEKEY'] = $oldEntry['RECORDNO'];
                            $oldEntry['SOURCE_DOCID'] = $recalledID;
                            unset($oldEntry['RECORDNO']);
                            $new['ENTRIES'][] = $oldEntry;
                        }
                    }

                    if ($this->_ismcpEnabled) {
                        $new['EXCHRATEDATE'] = GetCurrentDate();

                        $exchRateMgr = $gManagerFactory->getManager('exchangerate');
                        $basecurr = $new['BASECURR'] ?: GetBaseCurrency();

                        if ($new['CURRENCY'] != $basecurr) {
                            if ($new['EXCH_RATE_TYPE_ID'] == '-1') {
                                $new['EXCHRATE'] = $exchRateMgr->GetIntacctExchangeRate($new['CURRENCY'], $basecurr, $new['EXCHRATEDATE']);
                            } else {
                                $new['EXCHRATE'] = $exchRateMgr->GetTrxExchangeRateByTypeID($new['EXCH_RATE_TYPE_ID'], $new['CURRENCY'], $basecurr, $new['EXCHRATEDATE']);
                            }
                        } else {
                            $new['EXCHRATE'] = '';
                        }
                    }

                    $this->GetOrigDocDate($old, $new, $docpar);

                } elseif ($copy == 'Copy') {

                    $docpar = $this->GetBaseDocPar();
                    // remove the parent references for line items if this document is copied from a converted document
                    foreach ( $new['ENTRIES'] as $key => $entry) {
                        unset($new['ENTRIES'][$key]['RECORDNO']);
                        unset($new['ENTRIES'][$key]['BILLINGSCHEDULEKEY']);
                        unset($new['ENTRIES'][$key]['SOURCE_DOCKEY']);
                        unset($new['ENTRIES'][$key]['SOURCE_DOCLINEKEY']);
                        if ($docpar['DOCCLASS'] != 'Order') {
                            unset($new['ENTRIES'][$key]['BILLINGTEMPLATE']);
                        }
                    }
                    //while copying from one document to another document, we shouldn't carry the SCHOPKEY to the destination document
                    //Hence unsetting the SCHOPKEY
                    unset($new['SCHOPKEY']);

                    // the contact version might be old
                    // unset them to get the new versions
                    unset($new['SHIPTOKEY']);
                    unset($new['BILLTOKEY']);

                    // unset the following they might have copied form sales contract document
                    unset($new['SALESCONTRACT']);
                    unset($new['USEDASCONTRACT']);
                }

                // Since we're doing convert/copy from source document,
                // We should not carry create date/due date/GL posting date values from source document into converted/copyied document,
                // e.g. source could have been created in past but when we perform convert/copy operation,
                // the converted/copyied document should actually show create date = current date,
                // and due date should be recalculated based on term assigned (if any)
                // unset create date/due date values
                unset($new['WHENCREATED']);
                unset($new['WHENDUE']);
                unset($new['WHENPOSTED']);

                $this->ProcessCopyConvertSubtotals($new['SUBTOTALS']);

                // Do not copy 'sequence' field
                foreach ($destEntityMgr->customFields as $fieldid => $details) {
                    if ($details->type == 'SEQUENCE') {
                        unset($new[$fieldid]);
                    }
                }
                EntityManager::SetByPath($new, $destEntityMgr->GetKeyFieldName(), '');
            }
        }

        $new['DOCPARID'] = $destdoctype;

        if (Profile::hasProperty('SFORCEKEY') && Profile::getProperty('SFORCEKEY') != '') {
            $copy = Request::$r->_copymode;
            if ($copy != 'Update') {
                $new = $this->_PrepSalesforceValues($new, Profile::getProperty('SFORCEKEY'));
            }
        }

        $this->PreProcessEditorGetSubTotals($srcdoctype, $destdoctype, $old, $new, Profile::getProperty('SFORCEKEY'));
        //eppp_p($new);

        $this->EditorGetSubTotals($_params, $new, true);
        //eppp_p($new);

        // Give child classes oppertunity do additional processing
        $this->PostProcessCopyConvert($srcdoctype, $destdoctype, $old, $new);
        //eppp_p($new);
        //dieFL();

        if ($this->state != $this->kErrorState) {
            Request::$r->SetCurrentObject($new);
            $this->state = $this->kShowNewState;
        }
        return false;   // ?? before php71 conversion there was NO return statement
    }

    /**
     * @param array $subtotals
     */
    function ProcessCopyConvertSubtotals(&$subtotals)
    {
        // This function is to retain the subtotals of the source document if any when it is copied or converted
        //
        // the first [SUBTOTAL] and the last element [TOTAL] are not the subtotals

        // remove the [SUBTOTAL] & [TOTAL] elements from the ssubtotal structure
        $subtotcount = count($subtotals);
        if (isset($subtotals) && $subtotcount == 2) {
            unset($subtotals[0]);
            unset($subtotals[$subtotcount - 1]);
        }
        // now check if there are any actual subtotals left
        // if not then unset the subtotal section
        if (!count($subtotals)) {
            unset($subtotals);
        }

    }

    /**
     * @param string      $srcdoctype
     * @param string      $destdoctype
     * @param array       $old
     * @param array       $new
     * @param null|string $sfkey
     *
     * @return true
     * @throws Exception
     */
    function PreProcessEditorGetSubTotals($srcdoctype, $destdoctype, &$old, &$new, $sfkey)
    {
        //eppp_p("PreProcessEditorGetSubTotals");
        //eppp_p("srcdoctype:".$srcdoctype);
        //eppp_p("destdoctype:".$destdoctype);

        //eppp_p('SFORCEKEY:'.Profile::getProperty('SFORCEKEY'));

        if (isset($sfkey) && $sfkey != '') {
            $action = Request::$r->_action;
            //eppp_p("action:".$action);

            // Set the default value to OVERRIDETAX checkbox
            // only when drawing txn screen for first time
            if ($action != 'refresh') {
                global $gManagerFactory;
                $docparMgr = $gManagerFactory->getManager('documentparams');
                $itemMgr = $gManagerFactory->getManager('item');

                $newdocpar = $docparMgr->GetBaseLatest($destdoctype);
                $newenableoverride = $newdocpar['ENABLEOVERRIDETAX'];
                //eppp_p("newenableoverride:".$newenableoverride);

                if ($newenableoverride == 'true') {
                    //eppp_p($new['ENTRIES']);

                    $itemsArr = array();
                    foreach ( $new['ENTRIES'] as $entry) {
                        [$itemid] = explode('--', $entry['ITEMID']);
                        if (!in_array($itemid, $itemsArr)) {
                            $itemsArr[] = $itemid;
                        }
                    }

                    $itemRawCache = $itemMgr->GetItemsRawCache($itemsArr);

                    for ($i = 0; $i < count($new['ENTRIES']); $i++) {
                        [$itemid] = explode('--', $new['ENTRIES'][$i]['ITEMID']);
                        //eppp_p("itemid:".$itemid);

                        //eppp_p($itemraw);

                        $taxable = $itemRawCache[$itemid]['TAXABLE'];
                        //eppp_p("taxable:".$taxable);

                        $new['ENTRIES'][$i]['OVERRIDETAX'] = ($taxable == 'T') ? 'true' : 'false';
                    }
                }
            }

            return true;
        }

        if ($srcdoctype == "" || $destdoctype == "") {
            return true;
        }

        // _DOCPAR is not set, fetching it
        // DocumentparamsManager::GetBaseLatest caches information
        // There is no risk of hitting database too many times

        global $gManagerFactory;
        $docparMgr = $gManagerFactory->getManager('documentparams');
        $olddocpar = $docparMgr->GetBaseLatest($srcdoctype);
        //eppp_p($olddocpar);

        $newdocpar = $docparMgr->GetBaseLatest($destdoctype);
        //eppp_p($newdocpar);

        // ENABLEOVERRIDETAX functionality is not applicable for IC
        // Value 'false' will make sure code is not executed
        $oldenableoverride = $olddocpar['ENABLEOVERRIDETAX'];
        $newenableoverride = $newdocpar['ENABLEOVERRIDETAX'];
        //eppp_p("oldenableoverride:".$oldenableoverride);
        //eppp_p("newenableoverride:".$newenableoverride);

        // If destination document has subscribed to override tax  but source document has not
        // then "Override Tax" tax checkbox value should be defaulted to ITEM.TAXABLE value
        if ($newenableoverride == 'true' && $oldenableoverride != 'true') {
            for ($i = 0; $i < count($new['ENTRIES']); $i++) {
                $new['ENTRIES'][$i]['OVERRIDETAX'] = $old['ENTRIES'][$i]['ITEM']['TAXABLE'];
            }
        }

        return true;
    }

    /**
     * @param string $srcdoctype
     * @param string $destdoctype
     * @param array  $old
     * @param array  $new
     *
     * @return true
     */
    function PostProcessCopyConvert(
        /** @noinspection PhpUnusedParameterInspection */ $srcdoctype,
        /** @noinspection PhpUnusedParameterInspection */ $destdoctype,
        /** @noinspection PhpUnusedParameterInspection */ &$old,
        /** @noinspection PhpUnusedParameterInspection */ &$new)
    {
        return true;
    }


    /**
     * @param string  $ownerObject
     * @param string $type
     *
     * @return array
     */
    function GetCustomComponents($ownerObject, $type = "all")
    {
        if (!isset($type) || $type == "") {
            $type = "all";
        }
        $cny = GetMyCompany();
        $ret_fields = array();
        $ret_links = array();

        // For SCM owner objects
        $CF_doctypejoin = " ";
        $SL_doctypejoin = " ";
        $custOwnerObj = false;

        import('DocumentManager');
        if ( $this instanceof self || $this instanceof \RecurDocumentEditor ) {
            $doctype = $this->dt;

            $docid = Request::$r->_r;
            if ($doctype == '' && $docid != '') {
                $doctype = GetDocumentType($docid);
            }
            $queryArr = array('', $cny, $ownerObject);
            if ($doctype != '') {
                $CF_doctypejoin = " and (cf.doctype = 'ALL' or '#~#'||cf.doctype||'#~#' like '%#~#'||:3||'#~#%') ";
                $SL_doctypejoin = " and (sl.doctype = 'ALL' or '#~#'||sl.doctype||'#~#' like '%#~#'||:3||'#~#%') ";
                $queryArr[] = $doctype;
            }

            if ( $this instanceof \RecurDocumentEditor ) {
                $custOwnerObj = true;
            }
        }

        /**
         * @var DocumentManager $docMgr
         */
        $docMgr = $this->GetManager('document');

        if ($type == "all" || $type == "customfield") {
            // Check whether custom fields exist for this object

            $ownerObject = ($custOwnerObj) ? $this->GetCustomOwnerObject($ownerObject) : $ownerObject;
            $queryArr[2] = $ownerObject;
            $queryArr[3] = getUserLocale();

            /** @noinspection PhpUndefinedVariableInspection */
            $custFldExist = $docMgr->HasCustomFields($ownerObject, $doctype);

            // Do query only if custom fields exist for this object
            if ($custFldExist) {
                $qry =
                    "
                select cc.COMPONENTTYPE, cc.PATH, cc.LABEL as OLABEL, cc.HIDDEN, clc.PAGE, clc.FIELDSET, cf.OBJECTFIELDID, cl.LABEL
                from customcomponent cc, customlayoutcomponent clc, customfield cf, customlabel cl
                where
                cf.ownerobject = :2
                $CF_doctypejoin
                and cf.active = 'T'
                and cc.customfieldkey = cf.record#
                and cc.record# = clc.customcomponentkey
                and cc.cny# = :1
                and clc.cny# = :1
                and cf.cny# = :1
                and cl.cny#(+) = :1
                and cl.locale(+) = :3
                and cl.id(+) = cc.customlabelid                
                order by to_number(substr(cf.OBJECTFIELDID,10))
                ";

                $queryArr[0] = $qry;

                $ret_fields = QueryResult($queryArr);
            }
        }
        // Smart Links
        if ($type == "all" || $type == "smartlink") {
            // Check whether smart links exist for this object
            /** @noinspection PhpUndefinedVariableInspection */
            $smartLnkExist = $docMgr->HasSmartLinks($ownerObject, $doctype);

            // Do query only if smart links exist for this object
            if ($smartLnkExist) {
                $qry =
                    "
                select cc.COMPONENTTYPE, cc.PATH, cc.LABEL, cc.HIDDEN, clc.PAGE, clc.FIELDSET
                from customcomponent cc, customlayoutcomponent clc, smartlink sl
                where
                sl.ownerobject = :2
                $SL_doctypejoin
                and sl.active = 'T'
                and cc.smartlinkkey = sl.record#
                and cc.record# = clc.customcomponentkey
                and cc.cny# = :1
                and clc.cny# = :1
                and sl.cny# = :1
                ";

                $queryArr[0] = $qry;

                $ret_links = QueryResult($queryArr);
            }
        }
        $ret = INTACCTarray_merge($ret_fields, $ret_links);
        return $ret;
    }

    /**
     * @param array $_params
     *
     * @return mixed
     */
    function MergeLayout($_params)
    {
        $docpar = $this->GetBaseDocPar();

        // Override tax functionality is not implemented in recurring docs
        $fromRecurrEditor = $this instanceof \ScheduledDocumentEditor;
        //eppp_p("fromRecurrEditor:".$fromRecurrEditor);

        // if enableoverride tax is enabled show taxable checkbox.
        if (!$fromRecurrEditor && $docpar['ENABLEOVERRIDETAX'] == 'true') {
            foreach ($_params['pages'] as $pgindx => $page) {
                if (!strcmp($page['title'], "Line Items")) {
                    foreach ($_params['pages'][$pgindx]['fields'] as $fldindx => $field) {
                        if (!strcmp($field['path'], "ENTRIES")) {
                            foreach ($field['columns'] as $key => $fld) {
                                if ($fld['path'] == 'AVAILLINK') {
                                    //$next = $field['columns'][$key+1];
                                    $reqKey = $key + 1;
                                    $newar = array_slice($_params['pages'][$pgindx]['fields'][$fldindx]['columns'], 0, $reqKey);
                                    $newar[] = array('path' => 'OVERRIDETAX');
                                    $newar = INTACCTarray_merge($newar, array_slice($_params['pages'][$pgindx]['fields'][$fldindx]['columns'], $reqKey));
                                    $_params['pages'][$pgindx]['fields'][$fldindx]['columns'] = $newar;
                                }
                            }
                        }
                    }
                }
            }
        }

        return parent::MergeLayout($_params);
    }

    /**
     * @param array $_params
     *
     * @return mixed
     */
    function Editor_Expand($_params)
    {
        $source = "DocumentEditor::Editor_Expand";
        StartTimer($source);

        //$doctype = Request::$r->_dt;
        $entityMgr = $this->GetManager($_params['entity']);
        if ($this->ProcessErrorRetrivalAction($entityMgr)) {
            $obj = Request::$r->GetCurrentObject();
            Request::$r->_dt = $obj['DOCPARID'];
            $this->_fromError = true;
        } else {
            $this->_fromError = false;
        }

        //$docparMgr = $gManagerFactory->GetManager('documentparams');
        $docMgr = $this->GetManager($this->mod . 'document');

        $docid = Request::$r->_r;
        //$_do = Request::$r->_do;
        $cat = Request::$r->_cat;

        if (!$this->dt) {
            $entityMgr = $this->GetManager($_params['entity']);
            if ($docid) {
                $rec = $entityMgr->DoQuery('QRY_DOCUMENT_GET_DOCPARID', array($docid));
                $this->dt = $rec[0]['DOCID'];
            } else {
                //the flag _doctypeeditable is used on refresh to decide whether the field is editable
                $this->_doctypeeditable = true;
                $docs = GetDocumentParams($this->mod, $cat);
                $this->dt = $docs[0];
            }
            if (isset($this->dt) && $this->dt != '') {
                Request::$r->_dt = $this->dt;
            }
        }

        if (isset($this->dt) && $this->dt != '') {
            $docparmrec = $this->GetBaseDocPar();
        }

        /** @noinspection PhpUndefinedVariableInspection */
        $this->_deptOverride = ( $docparmrec['DEPTOVERRIDE'] == 'true');
        $this->_locOverride = ($docparmrec['LOCOVERRIDE'] == 'true');

        //call the change contact labels method here
        $this->ChangeContactLabels($docparmrec, $_params);

        if (isset($docparmrec) && $docparmrec['SHOW_TOTALS'] == 'true') {
            /**** This guy should be ideally done in an XML w'll need to figure out some way ****/
            $scolumns = array();
            $absval = array(
                'path'      => 'ABSVAL',
                'fullname'  => 'Value',
                'type'      => array(
                    'ptype'            => 'currency',
                    'multilinecolsepr' => 30,
                ),
                'size'      => 5,
                'maxlength' => 12,
                'subtotal'  => 1,
            );
            /** @noinspection PhpUndefinedVariableInspection */
            $total = array(
                'path'     => 'TOTAL',
                'fullname' => 'Total',
                'size'     => 10,
                'type'     => array(
                    'ptype'            => 'currency',
                    'type'             => $gCurrencyFormat,
                    'multilinecolsepr' => 50,
                    'blankwhenzero'    => true
                ),
                'readonly' => 1,
                'subtotal' => 1,
            );
            $trxabsval = array(
                'path'      => 'TRX_ABSVAL',
                'fullname'  => 'Value',
                'type'      => array(
                    'ptype'            => 'currency',
                    'type'             => $gCurrencyFormat,
                    'multilinecolsepr' => 30,
                ),
                //'onchange' => 'UpdateBase_absval(this);',
                'size'      => 5,
                'maxlength' => 12,
                'subtotal'  => 1
            );
            $trxtotal = array(
                'path'     => 'TRX_TOTAL',
                'fullname' => 'Total',
                'size'     => 10,
                'type'     => array(
                    'ptype'            => 'currency',
                    'type'             => $gCurrencyFormat,
                    'multilinecolsepr' => 50,
                    'blankwhenzero'    => true
                ),
                'readonly' => 1,
                'subtotal' => 1
            );
            if ($docparmrec['DISPLAY_BASECURRENCY'] == 'true') {
                $trxabsval['fullname'] = 'Transaction Value';
                $trxtotal['fullname'] = 'Transaction Total';
            }
            $scolumns[] = array(
                'path'     => 'DESCRIPTION',
                'fullname' => 'Description',
                'size'     => 10,
                'readonly' => 1,
                'subtotal' => 1,
                'required' => false,
            );
            $scolumns[] = array(
                'path'      => 'PERCENTVAL',
                'fullname'  => 'Percent',
                'type'      => array(
                    'multilinecolsepr' => 30,
                ),
                'size'      => 5,
                'maxlength' => 12,
                'subtotal'  => 1
            );
            if ($this->_ismcpEnabled) {
                $absval['hidden'] = 1;
                $total['hidden'] = 1;

                $scolumns[] = $trxabsval;
                if ($docparmrec['DISPLAY_BASECURRENCY'] == 'true') {
                    $absval['fullname'] = 'Base Value';
                    $absval['hidden'] = 0;
                    $scolumns[] = $absval;
                }
                $scolumns[] = $trxtotal;
                if ($docparmrec['DISPLAY_BASECURRENCY'] == 'true') {
                    $total['fullname'] = 'Base Total';
                    $total['hidden'] = 0;
                    $scolumns[] = $total;
                }
            } else {
                $scolumns[] = $absval;
                $scolumns[] = $total;
            }

            $isRootContext = false;
            if (IsMultiEntityCompany() && !GetContextLocation()) {
                $isRootContext = true;
            }

            if ($this->_deptOverride) {
                $onchange = NULL;
                if (!util_isPlatformDisabled() && Pt_StandardUtil::autoFillRelated('department')) {
                    $onchange = 'pt_editor_defaultRelated(this, null);';
                }

                $deptVal = array(
                    'path'       => 'DEPARTMENT',
                    'subtotal'   => 1,
                    'renameable' => 1,
                    'onchange'   => $onchange
                );
                if ($isRootContext) {
                    // For a MEGA root context, this value is readonly and will inherit from the document header
                    $deptVal['readonly'] = 1;
                }
                $scolumns[] = $deptVal;
            }

            if ($this->_locOverride && !$isRootContext) {
                $onchange = NULL;
                if (!util_isPlatformDisabled() && Pt_StandardUtil::autoFillRelated('location')) {
                    $onchange = 'pt_editor_defaultRelated(this, null);';
                }

                $scolumns[] = array(
                    'path'       => 'LOCATION',
                    'subtotal'   => 1,
                    'renameable' => 1,
                    'onchange'   => $onchange
                );
            }

            if ($this->_ismcpEnabled && $docparmrec['DISPLAY_BASECURRENCY'] != 'true') {
                $scolumns[] = $absval;
                $scolumns[] = $total;
            }

            //Fix me for the module based dimension ent's, mgrs
            $lineitementity = $this->mod . 'documentsubtotals';

            // merge in dimensions
            $sdimcolumns = $this->getDimensionFieldsInfo($lineitementity);
            //$this->MergeOwnedObjectDimensions('documentsubtotals', $sdimcolumns);

            if (count($sdimcolumns) > 0) {
                $primaryDim = $this->getEntityMgr()->getPrimaryDimensions();

                foreach ($sdimcolumns as $key => $sdimcolumn) {

                    if (isset($primaryDim[$sdimcolumn['path']])) {
                        // Hide those dimensions that are not part of the module.
                        $sdimcolumns[$key]['hidden'] = true;
                    } else if ($isRootContext) {
                        // For a MEGA root context, this value is readonly and will inherit from the document header
                        $sdimcolumns[$key]['readonly'] = true;
                    }
                }

                $scolumns = INTACCTarray_merge($scolumns, $sdimcolumns);
            }

            if (!util_isPlatformDisabled()) {
                $this->mergeSubtotalCustomDimensions($scolumns);
            }

            $scolumns[] = array('path' => 'PERCENTEDIT', 'fullname' => 'Percent Edit', 'size' => 0, 'subtotal' => 1, 'hidden' => 1);
            $scolumns[] = array('path' => 'ABSEDIT', 'fullname' => 'Absolute Edit', 'size' => 0, 'subtotal' => 1, 'hidden' => 1);
            $scolumns[] = array('path' => 'BASELINE', 'fullname' => 'BaseLine', 'size' => 0, 'subtotal' => 1, 'hidden' => 1);
            $scolumns[] = array('path' => 'DISC_CHARGE', 'fullname' => 'Discount Charge', 'size' => 0, 'subtotal' => 1, 'hidden' => 1);
            $scolumns[] = array('path' => 'APPORTIONED', 'fullname' => 'Apportioned', 'size' => 0, 'subtotal' => 1, 'hidden' => 1);
            $scolumns[] = array('path' => 'GLACCOUNTKEY', 'fullname' => 'GL Account', 'size' => 0, 'subtotal' => 1, 'hidden' => 1);
            $scolumns[] = array('path' => 'DEB_CRED', 'fullname' => 'Debit Credit', 'size' => 0, 'subtotal' => 1, 'hidden' => 1);
            $scolumns[] = array('path' => 'ISTAX', 'fullname' => 'Is Tax', 'size' => 0, 'subtotal' => 1, 'hidden' => 1);
            $scolumns[] = array('path' => 'TAXDETAIL', 'fullname' => 'Tax Detail', 'size' => 0, 'subtotal' => 1, 'hidden' => 1);


            $sfield = array(
                'path'        => 'SUBTOTALS',
                'title'       => 'IA.SUB_TOTALS',
                'fullname'    => 'IA.SUB_TOTALS',
                '_func'       => 'MultilineLayout',
                'varpath'     => 'SUBTOTALS',
                'varname'     => '_obj__SUBTOTALS',
                'maxvertical' => 1,
                'columns'     => $scolumns,
                'subtotal'    => 1
            );

            $_params['SHOWTOTALS'] = 1;

            for ($i = 0; $i < count($_params['pages']); $i++) {
                if (!strcmp($_params['pages'][$i]['title'], "Line Items")) {
                    $_params['pages'][$i]['fields'][] = $sfield;
                    break;
                }
            }


        }

        if (isset($docparmrec) && $docparmrec['ENABLESCHEDULE'] == 'true') {
            /**** This guy should be ideally done in an XML w'll need to figure out some way ****/
            $this->GetRecurHistoryFields($_params);
        }

        if ($this->dt && !$this->_doctypeeditable) {
            $_params['title'] = $this->dt;
        }

        $action = Request::$r->{$this->kAction};
        $state = Request::$r->_state;

        if (isset($docid)) {
            // Check if it was recalled by other Xactions, if so view only
            $props = array();
            // if there is no valid $cny then we can not find the pref
            // this happens at least in the make process.
            $cny = GetMyCompany();
            if (isset($cny) && $cny != '') {
                $props = $docMgr->DoQuery('QRY_DOCUMENT_IS_EDIT_INFO', array($docid));
            }
            $docTotalPaid = array();
            // if there is no valid $cny then we can not find the doc total paid
            // this happens at least in the make process.
            if (isset($cny) && $cny != '') {
                $docTotalPaid = $docMgr->DoQuery('QRY_DOCUMENT_IS_EDIT_INFO_TOTALPAID', array($props[0]['PRRECORDKEY']));
            }
        }
        // The convert link should be hidden for sales orders that are fully or partially converted.
        /** @noinspection PhpUndefinedVariableInspection */
        $this->_noConvertLink = ( $props[0]['STATE'] == 'C' || $props[0]['SALESCONTRACT'] == 'Y') ? true : false;


        if (($this->do == 'edit' || $this->do == 'view') && !($action == 'new' || $state == 'shownew')) {
            /** @noinspection PhpUndefinedVariableInspection */
            if (!$this->_IsTransactionEditable($docparmrec['EDITTYPE'], $props[0]['STATE'], $docTotalPaid[0]['TOTALPAID'])) {
                Request::$r->_do = 'view';
                $this->do = 'view';
                if (is_object($this->entityMgr)) {
                    $this->entityMgr->_canupdate = false;
                }
            }
        }

        //epp("TIMING: $source" . StopTimer($source));
        StartTimer("Editor_Expand");
        //epp("TIMING: Editor_Expand" . StopTimer("Editor_Expand"));
        return Editor::Editor_Expand($_params);
    }

    /**
     * @param string $entity
     * @param bool   $preserveKey
     *
     * @return array|null
     */
    function getDimensionFieldsInfo($entity, $preserveKey = false)
    {
        $nodes = parent::getDimensionFieldsInfo($entity, $preserveKey);

        foreach ( $nodes as $index => $node) {
            $nodes[$index]['autofill'] = '1';
            //$nodes[$index]['afterfunction'] = 'AutoFill';
        }

        return $nodes;
    }

    /**
     * Get multiline path, used for platform lookup fields
     *
     * @return string|null
     */
    function getMultilinePath()
    {
        if (self::$currentMultilinePath) {
            return self::$currentMultilinePath;
        }
        return 'ENTRIES';
    }


    /**
     * @param array $_params
     */
    function GetRecurHistoryFields(&$_params)
    {
        $scolumns = array();

        $scolumns[] = array('path' => 'DOCTYPE', 'fullname' => 'Document Type', 'size' => 20);
        $scolumns[] = array('path' => 'RECURRECNO', 'fullname' => '', 'size' => 20);
        $scolumns[] = array('path' => 'RECURTRANSACTION', 'fullname' => '', 'size' => 20);
        $scolumns[] = array('path' => 'LINENO', 'fullname' => 'Line No', 'size' => 20);
        $scolumns[] = array('path' => 'ITEMKEY', 'fullname' => 'Item ID', 'size' => 20);
        $scolumns[] = array('path' => 'MEMO', 'fullname' => 'Memo', 'size' => 20);
        $scolumns[] = array('path' => 'UIVALUE', 'fullname' => 'Amount', 'size' => 20);

        $sfield = array(
            'path'        => 'RECURHISTORY',
            'title'       => 'IA.LINE_ITEM_CONVERSION_TEMPLATES',
            'fullname'    => 'IA.LINE_ITEM_CONVERSION_TEMPLATES',
            '_func'       => 'MultilineLayout',
            'varpath'     => 'RECURHISTORY',
            'varname'     => '_obj__RECURHISTORY',
            'maxvertical' => 1,
            'columns'     => $scolumns,
        );

        for ($i = 0; $i < count($_params['pages']); $i++) {
            if (!strcmp($_params['pages'][$i]['title'], "History")) {
                $_params['pages'][$i]['fields'][] = $sfield;
                break;
            }
        }
    }


    /**
     * @param string                   $editpolicy
     * @param string                   $state
     * @param        int|float|string  $documentTotalPaid
     *
     * @return bool
     */
    function _IsTransactionEditable($editpolicy, $state, $documentTotalPaid)
    {

        if ($editpolicy == 'No Edit') {
            return false;
        } else {
            $recalledStates = array("C", "P", "G");
            // if the document is in Converted/Partial state
            $isRecalled = in_array($state, $recalledStates) ? true : false;

            if ($isRecalled) {
                return false;
            }
            if ($editpolicy == 'Before Printing') {
                // Is Document Printed
                /** @noinspection PhpUndefinedVariableInspection */
                if ( $res[0]['PRINTED'] == 'T') {
                    return false;
                }
            }

            //Is it paid
            if ($documentTotalPaid != '' && $documentTotalPaid != 0) {
                $this->_stateEditable = true;
                return false;
            }
        }
        return true;
    }

    /**
     * @param array $_params
     */
    function Editor_Instantiate(&$_params)
    {
        global $gManagerFactory, $gErr;

        $_sess = Session::getKey();
        parent::Editor_Instantiate($_params);

        if (Request::$r->_popup) {
            $obj = Request::$r->GetCurrentObject();
            $this->dt = $obj['DOCPARID'];
        }

        $this->isAdvancedSetup = IsAdvancedConfiguration();

        //$doctype 	= Request::$r->_dt;
        $entID = Request::$r->_entid;
        $date = Request::$r->_date;
        $recalled = Request::$r->_r;
        $copy = Request::$r->_copymode;
        $cat = Request::$r->_cat;

        $this->priceFetchDisabled = ($recalled != '' && $copy == 'Update') ? 1 : 0;

        $docMgr = $gManagerFactory->getManager('document');
        $docpar = $this->GetBaseDocPar();


        if ($docpar['ENABLE_DISCOUNT_CHARGE'] == 'false') {
            $this->MatchTemplates($_params['layout']['pages'][1], array('path' => 'DISCOUNTPERCENT'), $_foundarray);
            foreach ( $_foundarray as $i => $x) {
                $_foundarray[$i]['path'] = 'DISCOUNTPERCENT';
                $_foundarray[$i]['hidden'] = true;
            }

        }


        //hide BUNDLENUMBER/ALLOLINK field, these two fields only available under SO for vsoe purpose
        $this->MatchTemplates($_params, array('path' => 'BUNDLENUMBER'), $bundleGroupFields);
        foreach ( $bundleGroupFields as $i => $x) {
            $bundleGroupFields[$i]['hidden'] = true;
        }

        $this->MatchTemplates($_params, array('path' => 'ALLOLINK'), $alloFields);
        foreach ( $alloFields as $i => $x) {
            $alloFields[$i]['hidden'] = true;
        }

        //setting the default warehouse from TD to document header
        /*if ($docpar['WAREHOUSESELMETHOD']=='Use the default warehouse') {
        GetUserPreferences($upref);
        $def_whse=$upref['DEFAULT_WAREHOUSE'];
        if ($def_whse=='' && $docpar['DEFAULT_WAREHOUSE']!=''){
        $def_whse = $docpar['DEFAULT_WAREHOUSE'];
        }
        $this->MatchTemplates($_params, array('path' => 'WAREHOUSE.LOCATIONID'), $whseavail);

        foreach ($whseavail as $i => $x) {
         $whseavail[$i]['value'] = $def_whse;
        }
        }*/
        //end
        //to get the view link in the line entry screen level
        $this->MatchTemplates($_params['layout']['pages'][1], array('path' => 'ITEMID'), $itemidarr);
        foreach ( $itemidarr as $i => $x) {
            $itemidarr[$i]['assist'] = 'notfat';
        }
        //end

        if ('' === $docpar['ALLOWEDITBILLTO'] || 'false' === $docpar['ALLOWEDITBILLTO']) {
            $this->MatchTemplates($_params['layout']['pages'][0], array('path' => 'BILLTO.CONTACTNAME'), $billtoarr);
            foreach ( $billtoarr as $i => $x) {
                $billtoarr[$i]['noview'] = true;
                $billtoarr[$i]['nonew'] = true;
                $billtoarr[$i]['nopick'] = true;

            }
        }
        if ('' === $docpar['ALLOWEDITSHIPTO'] || 'false' === $docpar['ALLOWEDITSHIPTO']) {
            $this->MatchTemplates($_params['layout']['pages'][0], array('path' => 'SHIPTO.CONTACTNAME'), $shiptoarr);
            foreach ( $shiptoarr as $i => $x) {
                $shiptoarr[$i]['noview'] = true;
                $shiptoarr[$i]['nonew'] = true;
                $shiptoarr[$i]['nopick'] = true;
            }
        }

        if ($recalled && $this->state == 'shownew') {

            // Get the recalled doctype
            $raw = $docMgr->GetRaw($recalled);

            $ok = isset($raw[0]);

            if (!$ok) {
                $label = ($copy == 'Update') ? 'Convert' : 'Copy';
                $msg = _('No transaction with the ID ' . $recalled . ' exists.');
                $gErr->addError(
                    'BL01001973', __FILE__ . ':' . __LINE__,
                    'Unable to ' . $label,
                    $msg,
                    'Please use a valid transaction as your source.'
                );
                $ok = false;
            } else {
                if ($copy != 'Copy') {
                    $ok = ConversionManager::isDocumentConvertable($recalled);
                }
            }

            if (!$ok) {
                include_once 'popuperror.phtml';
                exit();
            }
        }

        $num_fields = count($_params['allfields']);

        // 1 - Get the customer/vendor
        $entType = ($this->mod == 'so') ? 'customer' : 'vendor';

        if ($entID == '') {
            // find it in the array (grumble)
            for ($num = 0; $num < $num_fields; $num++) {
                if ($_params['allfields'][$num]['path'] == 'CUSTVENDID') {
                    $entID = $_params['allfields'][$num]['value'];
                    break;
                }
            }
        }

        if ($entID != '') {
            [$entVID] = explode('--', $entID);
            $qry = 'QRY_DOCUMENT_GET_' . isl_strtoupper($entType) . '_FOR_EDIT';
            $entData = $docMgr->DoQuery($qry, array($entVID));
            $entData = $entData[0];
        }

        if ($entType == 'vendor') {
            // LOOP all fields
            global $kAPid;
            $billNoPref = GetPreferenceForProperty($kAPid, 'BILLNOREQUIRED');
        } else if ($entType == 'customer') {
            $sfismcp = GetPreferenceForProperty('38.SFDC', 'SFORCEISMCP');
        }
        $qtyConverted = 0;

        $currobj = Request::$r->GetCurrentObject();

        for ($num = 0; $num < $num_fields; $num++) {

            // Plug in the id to the tree
            $field =& $_params['allfields'][$num];

            if ($this->_deptOverride && $field['path'] == 'DEPARTMENT') {
                $field['hidden'] = false;
            }

            if ($this->_locOverride && $field['path'] == 'LOCATION') {
                $field['hidden'] = false;
            }

            if ($field['path'] == 'DOCPARID') {
                $validvaluesfunc = "return GetDocumentParams('$this->mod', '$cat');";
                $field['type'] = array(
                    'type'            => 'enum',
                    'ptype'           => 'enum',
                    'validvaluesfunc' => $validvaluesfunc,
                );

                $field['onchange'] = 'AutoPopulatedocparID(this.value)';

                if ($this->dt) {
                    $field['value'] = $this->dt;

                    //the flag _doctypeeditable is used on refresh to decide whether the field is editable
                    if (!$this->_doctypeeditable) {
                        $field['readonly'] = true;
                    }
                }
            }

            $hideFlds = array('UIPRICE', 'UIVALUE');
            if ($this->_ismcpEnabled) {
                array_push($hideFlds, 'TRX_PRICE');
                array_push($hideFlds, 'TRX_VALUE');
            }
            if (in_array($field['path'], $hideFlds) && $docpar['OVERRIDE_PRICE'] != 'true') {
                $field['disabled'] = true;

                if ($field['path'] == 'UIVALUE') {
                    //unset($field['type']['ptype']);
                    $field['nocalc'] = true;
                }

                if ($this->_ismcpEnabled && $field['path'] == 'TRX_VALUE') {
                    //unset($field['type']['ptype']);
                    $field['nocalc'] = true;
                }
            }

            if (($field['path'] == 'UIPRICE' || $field['path'] == 'UIVALUE') && $docpar['OVERRIDE_PRICE'] != 'true') {
                $field['visible'] = true;

                if ($field['path'] == 'UIVALUE') {
                    unset($field['type']['ptype']);
                }
            }

            if ($field['path'] == 'VENDORDOCNO') {
                /** @noinspection PhpUndefinedVariableInspection */
                $billnorequired = ( $billNoPref && $docpar['SALE_PUR_TRANS'] == 'Purchase' && $docpar['UPDATES_GL'] == 'A');
                if ($billnorequired) {
                    $_params['allfields'][$num]['required'] = true;
                }
                if ($docpar['SALE_PUR_TRANS'] != 'Purchase') {
                    $field['hidden'] = true;
                }
            }

            if ($field['path'] == 'WHENDUE') {
                if ($docpar['DOCCLASS'] == 'Order' && $docpar['SALE_PUR_TRANS'] == 'Sale') {
                    $field['fullname'] = 'Ship Date';
                    $field['desc'] = 'Ship Date';
                } else {
                    if ($docpar['DOCCLASS'] == 'Quote') {
                        $field['fullname'] = 'Expiration Date';
                        $field['desc'] = 'Expiration Date';
                    }
                }
                /** @noinspection PhpUndefinedVariableInspection */
                if ( ! $field['value'] && $this->state == 'shownew' && $duedate) {
                    $field['value'] = $duedate;
                }
            }

            if ($this->state == 'shownew' && $field['path'] == 'SHIPVIA') {
                if (!$field['value']) {
                    /** @noinspection PhpUndefinedVariableInspection */
                    $field['value'] = $entData['SHIPPINGMETHOD'];
                }
            }

            // we don't want to show the created by & Modified By label, when we are creating
            // the Purchase order i.e., when we click on the add button to create the purchase order
            if ($this->state == 'shownew' && $field['path'] == 'USERID') {
                $field['hidden'] = true;
            }
            if ($this->state == 'shownew' && $field['path'] == 'CREATEDUSERID') {
                $field['hidden'] = true;
            }
            ////

            if ($field['path'] == 'WHENCREATED') {

                if (!$field['value'] && $this->state == 'shownew') {
                    $field['value'] = GetCurrentDate();
                } else if ($date) {
                    $field['value'] = $date;
                }

                //				if ($this->state != 'shownew') {
                //					$field['readonly'] = true;
                //				}
                $date = $field['value'];
            }

            if ($field['path'] == 'CREATEDFROM' || $field['path'] == 'COPYFROM') {
                $field['type']['entity'] = $this->mod . 'document';
            }

            if ($this->state == 'shownew') {

                $ID = Request::$r->_r;

                if (!$ID) {
                    if ($field['path'] == 'CREATEDFROM') {
                        $field['fullname'] = 'Source Transaction';
                        if ($copy != 'Copy') {
                            $field['onchange'] = 'RefreshOnSourceTransSelect(\'Update\', this.value, true);';
                            if ($this->mod == 'so' || $this->mod == 'po') {
                                $field['showhash'] = true;
                            }
                        }
                    }
                    if ($field['path'] == 'COPYFROM') {
                        $field['onchange'] = 'RefreshOnSourceTransSelect(\'Copy\', this.value, true);';
                    }
                } else {
                    if ($field['path'] == 'CREATEDFROM') {
                        if ($copy != 'Copy') {
                            $field['value'] = $ID;
                        } else {
                            $field['value'] = '';
                        }
                        $field['readonly'] = true;
                    }
                }


                if ($field['path'] == 'DOCNO') {

                    // when new document is created
                    if (!$entID && !$recalled) {
                        $field['hidden'] = true;
                    } else { // copying/converting
                        // when converting
                        if ($copy == 'Update') {
                            // if inherit source document number is set to true
                            // the converted document carries forward the source document number
                            if ($docpar['INHERIT_SOURCE_DOCNO'] != 'true') {
                                $field['value'] = '';
                            }
                        } elseif ($copy == 'Copy') {
                            $field['value'] = '';
                        }
                    }


                    // if Sequnece Numbering is disabled when creating/copying/converting.
                    // User can edit Document Number
                    if (!isset($docpar['SEQUENCE']) || '' === $docpar['SEQUENCE']) {
                        $field['readonly'] = false;
                        $field['hidden'] = false;
                    }

                    $docno = $field['value'];
                }

                if ($field['path'] == 'NOTE' || $field['path'] == 'BACKORDER' || $field['path'] == 'PRINTED') {
                    $field['hidden'] = true;
                }
            } else {
                if ($field['path'] == 'QTY_CONVERTED') {
                    $qtyConverted = $qtyConverted + ibcabs($field['value']);
                }

                if ($field['path'] == 'CREATEDFROM') {
                    $field['readonly'] = true;
                }
                if ($field['path'] == 'PRINTED' && !$field['value']) {
                    $field['value'] = "No";
                }
                if ($field['path'] == 'NOTE' && !$field['value']) {
                    $field['hidden'] = true;
                }

                //attach the pick_url with the picker control for sorting based on docid in picker
                $r = Request::$r->_r;
                if ($field['path'] == 'RECURDOCNAME') {
                    $field['type']['pick_url'] = "picker.phtml?.r=" . urlencode($r) . "&.salecon=T";
                }

                if ($field['path'] == 'DOCNO') {
                    $docno = $field['value'];
                }
            }

            if ($field['path'] == 'STATE') {

                if (!isset($field['value']) && !in_array($this->dt, array(BUILD_KIT, $this->dt != DIS_KIT))) {
                    $field['value'] = 'Pending';
                }

                if (in_array($field['value'], array('Draft', 'Submitted', 'Partially Approved', 'Approved', 'Declined', 'In Progress', 'Closed'))) {
                    $this->_noConvertLink = true;
                }

                if ((isset($currobj['ORIGSTATE']) && $currobj['ORIGSTATE'] == 'Draft') || ($this->state == $this->kShowNewState) && !in_array($this->dt, array(BUILD_KIT, DIS_KIT))) {
                    $field['value'] = 'Draft';
                }

                // Remove the system states like 'Submitted','Approved','Partially Approved','Declined'
                array_splice($field['type']['validvalues'], 0, 4);
                array_splice($field['type']['_validivalues'], 0, 4);
                if ((in_array($field['value'], array('Draft', 'Declined')) || $this->state == $this->kShowNewState) && $this->do != 'view') {
                    $_params['title'] = $_params['title'] . " -- Draft";
                    $this->showDraft = true;
                } else {
                    array_splice($field['type']['validvalues'], 0, 1);
                    array_splice($field['type']['_validivalues'], 0, 1);
                }

                for ($i = 0; $i < count($field['type']['validvalues']); $i++) {
                    if ($field['type']['validvalues'][$i] == 'In Progress') {
                        $fieldPos = $i;
                    }
                }

                /** @noinspection PhpUndefinedVariableInspection */
                array_splice($field['type']['validvalues'], $fieldPos, count($field['type']['validvalues']));
                array_splice($field['type']['_validivalues'], $fieldPos, count($field['type']['validvalues']));

                if ($this->_stateEditable) {
                    $field['readonly'] = false;
                }

                if (in_array($field['value'], array('Draft', 'Declined')) && $this->state != $this->kShowNewState) {
                    $field['readonly'] = true;
                }
            }

            if ($field['path'] == 'TERM.NAME') {

                if ($docpar['SALE_PUR_TRANS'] == 'Internal') {
                    $field['hidden'] = true;
                    continue;
                }

                $termmod = ($this->mod == 'so') ? 'ar' : 'ap';
                $field['type']['entity'] = $termmod . 'term';

                if ($this->state == 'shownew') {
                    if ($field['value'] != '') {
                        $termMgr = $gManagerFactory->getManager($field['type']['entity']);
                        $term = $termMgr->GetRaw($field['value']);
                        $term = $term[0];
                    } else {
                        /** @noinspection PhpUndefinedVariableInspection */
                        $termKey = ( $entData['TERMSKEY'] != '') ? $entData['TERMSKEY'] : $docpar['TERMKEY'];
                        if ($termKey != '') {
                            GetTerm($termKey, $term);
                        }
                    }

                    /** @noinspection PhpUndefinedVariableInspection */
                    if ($term) {

                        $field['value'] = $term['NAME'];

                        if (!$date) {
                            for ($n = 0; $n < $num_fields; $n++) {
                                if ($_params['allfields'][$n]['path'] == 'WHENCREATED') {
                                    $date = $_params['allfields'][$n]['value'];
                                }
                            }
                        }
                        // Calculate duedate for 'Invoice' type documents OR
                        // If coming from SFDC and term is mapped from SFDC via fieldmap
                        if (isl_strtoupper($docpar['DOCCLASS']) == 'INVOICE'
                            || (Profile::hasProperty('SFORCEKEY') && Profile::getProperty('SFORCEKEY') != '')
                        ) {
                            // $storageFormatDate = FormatDateForStorage($date);
                            // $duedate = CalcDueDate($storageFormatDate, $term['VALUE']);
                            $duedate = CalcDueDate($date, $term['VALUE']);
                        } else {
                            $duedate = $date;
                        }
                    }
                }
            }

            if ($field['path'] == 'CUSTVENDID' && ($this->mod == 'so' || $this->mod == 'po')) {

                $field['fullname'] = isl_ucfirst($entType) . " ID";
                $field['type']['entity'] = $entType;
                /** @noinspection PhpUndefinedVariableInspection */
                if ($entVID) {
                    /** @noinspection PhpUndefinedVariableInspection */
                    $field['value'] = $entVID . '--' . $entData['NAME'];
                }

                if ($this->state == 'shownew' && $copy != 'Update') {
                    if ($copy == 'Copy') {
                        $field['required'] = true;
                    } else {
                        $field['showhash'] = true;
                    }
                    $field['onchange'] = 'AutoPopulateCustVendID(this.value,\'true\');';
                    if ($this->mod == 'po') {
                        $field['primaryDimension'] = 'VENDORID';
                        if (IsMultiVisibilitySubscribed('vendor')) {
                            $qop = GetOperationId('ap/lists/vendor');
                            $field['onchange'] .= "FilterRestrictions('vendor', this.value, 'locationpick', '$_sess', '$qop'); FilterRestrictions('vendor', this.value, 'departmentpick', '$_sess', '$qop');";
                        }
                    } elseif ($this->mod == 'so') {
                        $field['onchange'] .= "RestrictProjectDimension('" . $field['varname'] . "','CUSTOMER','ENTRIES'," . GetOperationId('ar/lists/project') . ");";
                        if (IsMultiVisibilitySubscribed('customer')) {
                            $qop = GetOperationId('ar/lists/customer');
                            $field['onchange'] .= "FilterRestrictions('customer', this.value, 'locationpick', '$_sess', '$qop'); FilterRestrictions('customer', this.value, 'departmentpick', '$_sess', '$qop');";
                        }
                    }
                } else {
                    $field['readonly'] = true;

                }

                for ($n = 0; $n < $num_fields; $n++) {

                    // Extract out values of certain fields
                    // This is to check  if the contactversion has changed, if not, then don't display the checkbox
                    $field =& $_params['allfields'][$n];
                    switch ($field['path']) {
                        case 'SHIPTO.CONTACTNAME':
                            $shiptoName = $field['value'];
                            break;
                        case 'SHIPTOKEY':
                            $shiptoKey = $field['value'];
                            break;
                        case 'GETLATESTSHIPTO':
                            $shiptoCheckbox =& $field;
                            break;
                        case 'BILLTO.CONTACTNAME':
                            $billtoName = $field['value'];
                            break;
                        case 'BILLTOKEY':
                            $billtoKey = $field['value'];
                            break;
                        case 'GETLATESTBILLTO':
                            $billtoCheckbox =& $field;
                            break;
                    }

                    if (in_array($field['path'], array('BILLTO.CONTACTNAME', 'SHIPTO.CONTACTNAME'))) {
                        $field['fullname'] = "";
                    }

                    // Check if the SFDC company is mcp enabled and also intacct company is mcp enabled and set the so document when created from SFDC have the multicurrency fields in view mode.
                    /** @noinspection PhpUndefinedVariableInspection */
                    if ( $sfismcp == 'true' && $this->_ismcpEnabled) {

                        if (Profile::hasProperty('SFORCEKEY') && Profile::getProperty('SFORCEKEY') != '') {

                            switch ($field['path']) {

                                case 'CURRENCY':
                                    $field['readonly'] = true;
                                    break;
                            }
                        }
                    }
                }

                if ($this->state != 'showedit' && $copy != 'Update') {
                    for ($n = 0; $n < $num_fields; $n++) {
                        if (in_array($_params['allfields'][$n]['path'], array('GETLATESTSHIPTO', 'GETLATESTBILLTO'))) {
                            $_params['allfields'][$n]['hidden'] = true;
                        }
                    }
                } else {
                    $contactMgr = $gManagerFactory->getManager('contact');

                    /** @noinspection PhpUndefinedVariableInspection */
                    if ( !$shiptoKey || $contactMgr->GetCurrentVersionNo($shiptoName) == $shiptoKey) {
                        $shiptoCheckbox['hidden'] = true;
                    }
                    /** @noinspection PhpUndefinedVariableInspection */
                    if ( !$billtoKey || $contactMgr->GetCurrentVersionNo($billtoName) == $billtoKey) {
                        $billtoCheckbox['hidden'] = true;
                    }
                }

                // Get shipto/billto for the first time as defaults
                if ($this->state == 'shownew') {
                    /** @noinspection PhpUndefinedVariableInspection */
                    $shipto = ($shiptoName) ?: $entData['SHIPTONAME'];

                    /** @noinspection PhpUndefinedVariableInspection */
                    if ( !$shipto && $entData['VISIBLE'] == 'T') {
                        $shipto = $entData['DISPLAYCONTACTNAME'];
                    }

                    /** @noinspection PhpUndefinedVariableInspection */
                    $billto = ($billtoName) ?: $entData['BILLTONAME'];

                    /** @noinspection PhpUndefinedVariableInspection */
                    if ( !$billto && $entData['VISIBLE'] == 'T') {
                        $billto = $entData['DISPLAYCONTACTNAME'];
                    }

                    for ($n = 0; $n < $num_fields; $n++) {

                        if ($_params['allfields'][$n]['path'] == 'SHIPTO.CONTACTNAME') {
                            if (!isset($_params['allfields'][$n]['value'])
                                || $_params['allfields'][$n]['value'] == '' || $copy == 'Copy'
                            ) {
                                $_params['allfields'][$n]['value'] = $shipto;

                                // Set into request also
                                $currobj['SHIPTO']['CONTACTNAME'] = $shipto;
                            }
                        }

                        if ($_params['allfields'][$n]['path'] == 'BILLTO.CONTACTNAME') {

                            if (!isset($_params['allfields'][$n]['value'])
                                || $_params['allfields'][$n]['value'] == '' || $copy == 'Copy'
                            ) {
                                $_params['allfields'][$n]['value'] = $billto;

                                // Set into request also
                                $currobj['BILLTO']['CONTACTNAME'] = $billto;
                            }
                        }

                        if ($_params['allfields'][$n]['path'] == 'CUSTVENDNAME') {
                            /** @noinspection PhpUndefinedVariableInspection */
                            $_params['allfields'][$n]['value'] = $entData['NAME'];
                            $_params['allfields'][$n]['fullname'] = isl_ucfirst($entType) . " name";
                            $_params['allfields'][$n]['readonly'] = true;
                        }// endif custvendname
                    }//endif shownew

                    // Update request also
                    Request::$r->SetCurrentObject($currobj);
                }
            }//if custvendid

            if ($field['path'] == 'VIRTUAL.CUSTVENDID') {
                /** @noinspection PhpUndefinedVariableInspection */
                if ($entVID) {
                    /** @noinspection PhpUndefinedVariableInspection */
                    $field['value'] = $entVID . '--' . $entData['NAME'];
                }
            }

            if ($field['path'] == 'VIRTUAL.DOCPARID') {
                $field['value'] = $this->dt;
            }

            if ($field['path'] == 'VIRTUAL.WHENCREATED') {
                $field['value'] = (($this->state != 'showview' && Request::$r->_action != 'refresh') ? FormatDateForDisplay($date) : $date);
            }

            if ($field['path'] == 'VIRTUAL.DOCNO') {
                /** @noinspection PhpUndefinedVariableInspection */
                $field['value'] = $docno;
            }

        }//end for

        // hide the qty_converted field if non of the lines are converted
        $qtyConvFields = array();
        $this->MatchTemplates($_params['layout']['pages'][1], array('path' => 'QTY_CONVERTED'), $qtyConvFields);
        foreach ( $qtyConvFields as $i => $x) {
            if ($qtyConverted == 0) {
                $qtyConvFields[$i]['hidden'] = 1;
            }
        }

        //Move focus on the history tab of the document if clicked on the link "SalesContract" in lister
        if (Request::$r->_issalescontract == 'Y') {
            Request::$r->_currentlayer = 'Layer2';
        } else {
            if ($this->state == 'shownew') {
                if (!Request::$r->_currentlayer) {
                    Request::$r->_currentlayer = 'Layer0';
                }
            } else {
                //This is not explicitly set by default, which causes js issues as a lot of code is built upon the reliance of this layer value
                $_hist = Request::$r->_hits;
                $_popup = Request::$r->_popup;
                if ($_hist && $_popup) {
                    Request::$r->_currentlayer = 'Layer2';
                } else {
                    Request::$r->_currentlayer = 'Layer1';
                }
            }
        }


        $hideLocDept = 0;
        $contextLocation = GetContextLocation();
        if ($docpar['LOCOVERRIDE'] == 'true') {
            //checking if the params has subtotals set $hideLocDept to 1
            $f = array();
            $this->MatchTemplates($_params['layout']['pages'][1], array('path' => 'SUBTOTALS'), $f);
            foreach ( $f as $i => $x) {
                if ($f[$i]['subtotal'] == 1) {
                    $hideLocDept = 1;
                }
            }
        }

        if (IsMultiEntityCompany() && !$contextLocation && $hideLocDept == 1) {

            $subtotalEntity = $this->mod . 'documentsubtotals';

            //only if params has subtotals do the hiding of location/dept
            $fields = array();
            $this->MatchTemplates($_params['layout']['pages'][1], array('path' => 'LOCATION'), $fields);
            foreach ( $fields as $i => $x) {
                if ($fields[$i]['entity'] == $subtotalEntity) {
                    $fields[$i]['fullname'] = '';
                    $fields[$i]['readonly'] = 1;
                }
            }
            $fields = array();
            $this->MatchTemplates($_params['layout']['pages'][1], array('path' => 'DEPARTMENT'), $fields);
            foreach ( $fields as $i => $x) {
                if ($fields[$i]['entity'] == $subtotalEntity) {
                    $fields[$i]['fullname'] = '';
                    $fields[$i]['readonly'] = 1;
                }
            }
        }
        If (IsMultiEntityCompany() && $contextLocation && $hideLocDept == 1) {

            $subtotalEntity = $this->mod . 'documentsubtotals';

            //Get the total number of rows in subtotals section
            $fields = array();
            $this->MatchTemplates($_params['layout']['pages'][1], array('title' => 'IA.SUB_TOTALS', 'path' => 'SUBTOTALS'), $fields);
            foreach ( $fields as $i => $x) {
                $subtotalRows = ibcsub($fields[$i]['actualnumofrows'], '1', 0);
            }

            //Since location is defaulted while creating transactions from entity, set location is null for the first and last row in subtotals
            $fields = array();
            $this->MatchTemplates($_params['layout']['pages'][1], array('path' => 'LOCATION'), $fields);
            foreach ( $fields as $i => $x) {
                /** @noinspection PhpUndefinedVariableInspection */
                if ( $fields[$i]['entity'] == $subtotalEntity && ( $fields[$i]['rownum'] == 0 || $fields[$i]['rownum'] == $subtotalRows)) {
                    $fields[$i]['value'] = '';
                }
            }
        }

        //
        // ----------- if multi currency is enabled ---------------
        //
        // show the currency if the 'Allow creating, editing & deleting foreign currency documents'
        // is set to true in OE Configuration
        if ($this->_ismcpEnabled) {
            if ($docpar['EXCH_RATE_TYPE_ID'] == '-1') {
                $exchTypeMgr = $gManagerFactory->getManager('exchangeratetypes');
                $docpar['EXCHRATETYPES']['NAME'] = $exchTypeMgr->GetExchangeRateTypeName($docpar['EXCH_RATE_TYPE_ID']);
            }
            $this->ShowMCPControls($_params, $docpar['EXCHRATETYPES']['NAME'], $docpar['DISPLAY_BASECURRENCY'], $docpar['OVERRIDE_EXCH_RATE_TYPE']);
        }

        if ($this->atlas) {
            $this->ShowAtlasControls($_params);
        }

        //hide view Recurring schedule if schopkey is not set
        //$this->MatchTemplates($_params, array('path' => 'SCHOPKEY'), $schopfields);
        if (!isset($currobj['SCHOPKEY'])) {
            $this->MatchTemplates($_params['layout']['pages'][1], array('path' => 'RECURRINGSCHEDULE'), $schfields);
            foreach ( $schfields as $i => $x) {
                $schfields[$i]['hidden'] = true;
                $schfields[$i]['readonly'] = 1;
                $schfields[$i]['hreftxt'] = '';
            }
        }

        $this->ProcessHideCostLink($_params);

        $this->ProcessHidePickLink($_params);

        // Sets if the document is owned by the current entity
        $this->_docIsOwned = $this->getEntityMgr()->_entityownership;

        $this->MatchTemplates($_params['layout']['pages'][0], array('path' => 'WHENPOSTED'), $postdatefields);
        if ($this->ShowGLPostingDate($docpar, $autofill)) {
            //$this->MatchTemplates($_params['layout']['pages'][0], array('path' => 'WHENPOSTED'), $postdatefields);
            foreach ( $postdatefields as $i => $x) {
                $postdatefields[$i]['hidden'] = false;
                if ($autofill && !$postdatefields['value'] && $this->state == 'shownew') {
                    if ($this->autoBatchFrequency == 'M') {
                        $postdatefields[$i]['value'] = GetCompanyLastDayOfCurrentPeriod();
                    } else {
                        $postdatefields[$i]['value'] = GetCurrentDate();
                    }
                }
            }
            if ($autofill) {
                $this->MatchTemplates($_params['layout']['pages'][0], array('path' => 'WHENCREATED'), $whencreatedflds);
                foreach ( $whencreatedflds as $i => $x) {
                    $whencreatedflds[$i]['onchange'] = 'ChangePostingDate();';
                }
            }
        } else if ($this->state == 'showedit') {
            //Edit action with GL Posting Date field as hidden, no need to send 'GL posting date' through editor
            foreach ( $postdatefields as $i => $x) {
                $postdatefields[$i]['value'] = '';
            }
        }
    }


    /**
     * @param array $_params
     */
    function ShowAtlasControls(&$_params)
    {

        if (!GetContextLocation()) {
            $qop = GetOperationId('co/lists/exchangerate/view');
            $_sess = Request::$r->_sess;
            $basecurr = GetBaseCurrency();
            $forma = GetUserDateFormat();

            $this->MatchTemplates($_params['layout']['pages'][1], array('path' => 'BASECURR'), $atlasfields);
            $this->MatchTemplates($_params['layout']['pages'][1], array('path' => 'CURRENCY'), $atlasfields);


            if ($this->mod != 'inv') {
                $this->MatchTemplates($_params['layout']['pages'][1], array('path' => 'LOCATION'), $atlasfields);
            }

            foreach ( $atlasfields as $i => $x) {
                if ($atlasfields[$i]['path'] == 'BASECURR') {
                    $atlasfields[$i]['hidden'] = false;
                    $atlasfields[$i]['required'] = true;
                    if ($this->state == 'showview') {
                        $atlasfields[$i]['readonly'] = true;
                    } else {
                        if ($this->_ismcpEnabled) {
                            $atlasfields[$i]['onchange'] = "UpdateExchangeRate(" .
                                "'$_sess', $qop, '$basecurr', '$forma');";
                        }
                    }
                }
                if ($atlasfields[$i]['path'] == 'LOCATION' && $atlasfields[$i]['fullname'] == 'Location') {
                    $atlasfields[$i]['required'] = true;
                }
            }
        } else {
            if ($this->do == 'view') {
                $this->MatchTemplates($_params['layout']['pages'][1], array('path' => 'BASECURR'), $currencyfields);
                foreach ( $currencyfields as $k => $fld) {
                    $currencyfields[$k]['hidden'] = false;
                }
            }

        }
    }


    /**
     * @param array       $_params
     * @param null|string $docpar_exchratename
     * @param string      $displaybaseCurrency
     * @param string      $overrideExchRateType
     *
     * @throws Exception
     */
    function ShowMCPControls(&$_params, $docpar_exchratename, $displaybaseCurrency = 'false', $overrideExchRateType = 'false')
    {
        global $gManagerFactory;

        $copymode = Request::$r->_copymode;
        $qop = GetOperationId('co/lists/exchangerate/view');
        $_sess = Session::getKey();
        $basecurr = GetBaseCurrency();

        $this->MatchTemplates($_params['layout']['pages'][1], array('path' => 'CURRENCY'), $currencyfields);
        $this->MatchTemplates($_params['layout']['pages'][1], array('path' => 'EXCHRATEDATE'), $currencyfields);
        $this->MatchTemplates($_params['layout']['pages'][1], array('path' => 'EXCHRATETYPES.NAME'), $currencyfields);
        $this->MatchTemplates($_params['layout']['pages'][1], array('path' => 'EXCHRATE'), $currencyfields);

        if ($currencyfields) {
            $exchMgr = $gManagerFactory->getManager('exchangeratetypes');
            $rtype = $exchMgr->GetDefaultExchangeRateType();
            $currentDate = GetCurrentDate();

            foreach ($currencyfields as $k => $fld) {
                $currencyfields[$k]['hidden'] = false;

                // add QRequest for getting exchange rate
                if ($fld['path'] != 'EXCHRATE') {
                    $currencyfields[$k]['onchange'] = "UpdateExchangeRate(" .
                        "'$_sess', $qop, '$basecurr');";

                    if ($fld['path'] == 'CURRENCY') {
                        $currencyfields[$k]['onchange'] .= "ReCalcBaseAmount();";
                    }
                } else {
                    if ($fld['value'] != '') {
                        $currencyfields[$k]['value'] = ibcmul($fld['value'], '1', 8, false);
                    }
                }

                if ($this->state == $this->kShowNewState) {
                    if ($fld['path'] == 'CURRENCY') {
                        $currencyfields[$k]['required'] = true;
                        if ($fld['value'] == '' && !Profile::getProperty('SFORCEKEY')) {
                            $currencyfields[$k]['value'] = $basecurr;
                        }
                        if ($copymode == 'Update') {
                            $currencyfields[$k]['readonly'] = true;
                        }
                    }

                    if ($fld['path'] == 'EXCHRATETYPES.NAME' && $fld['value'] == '') {
                        if (isset($docpar_exchratename) && $docpar_exchratename != '') {
                            $currencyfields[$k]['value'] = $docpar_exchratename;
                        } else {
                            $currencyfields[$k]['value'] = $rtype[0]['NAME'];
                        }
                    }
                    if ($fld['path'] == 'EXCHRATEDATE') {
                        if ($fld['value'] == '') {
                            $currencyfields[$k]['value'] = $currentDate;
                        }
                    }
                }

                if ($fld['path'] == 'EXCHRATETYPES.NAME' || $fld['path'] == 'EXCHRATE') {
                    if (isset($overrideExchRateType) && $overrideExchRateType != 'true') {
                        $currencyfields[$k]['disabled'] = true;
                        //unset($currencyfields[$k]['type']['ptype']);
                        $currencyfields[$k]['nocalc'] = true;
                    }
                }
            }
        }
        $pricefields = array();
        $this->MatchTemplates($_params['layout']['pages'][1], array('path' => 'UIPRICE'), $pricefields);
        $this->MatchTemplates($_params['layout']['pages'][1], array('path' => 'UIVALUE'), $pricefields);
        if ($pricefields) {
            foreach ($pricefields as $k => $fld) {
                $pricefields[$k]['disabled'] = true;
                $pricefields[$k]['hidden'] = ($displaybaseCurrency == 'true' ? false : true);//true;
                $pricefields[$k]['required'] = ($displaybaseCurrency == 'true' ? false : true);
                $pricefields[$k]['totaled'] = false;
                if ($fld['path'] == 'UIVALUE') {
                    //unset($pricefields[$k]['type']['ptype']);
                    $pricefields[$k]['nocalc'] = true;
                }
            }
        }

    }

    /**
     * @param array $_params
     *
     * @return mixed
     *
     * This function is to hide cost link in any mode other than edit and view
     */
    function ProcessHideCostLink(&$_params)
    {
        if (!($this->do == 'edit' || $this->do == 'view')) {
            $this->MatchTemplates($_params['layout']['pages'][1], array('path' => 'COSTLINK'), $fields);
            foreach ( $fields as $i => $x) {
                $fields[$i]['hidden'] = true;
                $fields[$i]['readonly'] = 1;
                $fields[$i]['hreftxt'] = '';
            }
        } else {
            $docid = Request::$r->_r;
            $affectsValue = IsDocumentAffectsValue($docid);

            if (!$affectsValue) {
                $this->MatchTemplates($_params['layout']['pages'][1], array('path' => 'COSTLINK'), $fields);
                foreach ( $fields as $i => $x) {
                    $fields[$i]['hidden'] = true;
                    $fields[$i]['readonly'] = 1;
                    $fields[$i]['hreftxt'] = '';
                }
            }
        }
        return $_params;
    }

    /**
     * @param array $_params
     *
     * @return mixed
     * @throws Exception
     */
    function ProcessHidePickLink(&$_params)
    {
        $cny = GetMyCompany();


        if (!($this->do == 'edit' || $this->do == 'view')) {

            if (isset($this->dt) && $this->dt != '') {
                $docparmrec = $this->GetBaseDocPar();
                $recordno = $docparmrec['RECORDNO'];
            }

        } else {
            $obj = Request::$r->GetCurrentObject();
            $recordno = $obj['DOCPARKEY'];
        }


        if ($this->isAdvancedSetup) {
            /** @noinspection PhpUndefinedVariableInspection */
            $affectsOnHandQty = IsDocumentAffectsOnHandQty($recordno);

            $userid = GetMyUserid(1);

            $permissionPickingList = IsPickingListReportPermission($cny, $userid);
            $permissionPhysicalInventory = IsPhysicalInventoryReportPermission($cny, $userid);

            $this->MatchTemplates($_params['layout']['pages'][1], array('path' => 'PICKLIST'), $fields);

            if ($permissionPhysicalInventory && $affectsOnHandQty) {
                foreach ( $fields as $i => $x) {
                    $fields[$i]['hidden'] = false;
                    $fields[$i]['readonly'] = 1;
                    $fields[$i]['hreftxt'] = 'Pick';
                }
            }

            $this->MatchTemplates($_params['layout']['pages'][0], array('path' => 'HDRPICKLINK'), $hdrfields);

            if ($permissionPickingList && $affectsOnHandQty && ($this->do == 'edit' || $this->do == 'view')) {
                foreach ( $fields as $i => $x) {
                    $hdrfields[$i]['hidden'] = false;
                    $hdrfields[$i]['readonly'] = 1;
                    $hdrfields[$i]['hreftxt'] = 'Print Pick List';
                }
            }
        }
        return $_params;
    }


    /**
     * @param array  $_field
     * @param string $layout used only in some descendants of Editor class
     * @param bool   $first  used only in some descendants of Editor class
     */
    function ShowFieldsRow(&$_field, $layout = "", $first = false)
    {
        //These fields are being displayed in ShowPayDateValue
        if ( in_array($_field['path'], array( 'COPYFROM', 'COPYMODE' )) ) {
            if ( ! $this->tempfields ) {
                $this->tempfields = array();
            }
            $this->tempfields[$_field['path']] = $_field;
        } else {
            Editor::ShowFieldsRow($_field);
        }
    }


    /**
     * @param array $_params
     *
     * @return mixed
     */
    function MultilineLayout_Expand($_params)
    {
        //$doctype 	= Request::$r->_dt;
        //$docparMgr	= $gManagerFactory->GetManager('documentparams');
        $docpar = $this->GetBaseDocPar();

        if ($_params['path'] == 'ENTRIES') {
            if ($_params['readonly'] || $this->_deptOverride || $this->_locOverride || $this->_ismcpEnabled) {
                foreach ($_params['columns'] as $ckey => $col) {
                    if ($col['_args']) {
                        foreach ($col['_args'] as $akey => $arg) {
                            if ($_params['readonly']) {
                                if ($arg['path'] == 'WAREHOUSEAVAIL') {
                                    $_params['columns'][$ckey]['_args'][$akey]['path'] = 'WAREHOUSE.LOCATION_NO';
                                }
                                if ($arg['path'] == 'UNITFACTOR') {
                                    $_params['columns'][$ckey]['_args'][$akey]['path'] = 'UNIT';
                                }
                            }
                            if ($arg['path'] == 'UIPRICE') {
                                $priceField = $arg;

                                if ($this->_ismcpEnabled) {
                                    $trxPrice = array('path'     => 'TRX_PRICE',
                                                      'autofill' => true,
                                                      'required' => true,
                                                      'fullname' => _('Price'));
                                    $_params['columns'][$ckey]['_args'][0] = $trxPrice;

                                    if ($docpar['DISPLAY_BASECURRENCY'] == 'true') {
                                        $priceField['fullname'] = _('Base price');
                                        $_params['columns'][$ckey]['_args'][] = $priceField;
                                    }
                                }

                                if ($this->_deptOverride) {
                                    $onchange = NULL;
                                    if (!util_isPlatformDisabled() && Pt_StandardUtil::autoFillRelated('department')) {
                                        $onchange = 'pt_editor_defaultRelated(this, null);';
                                    }

                                    $_params['columns'][$ckey]['_args'][] =
                                        array('path'      => 'DEPARTMENT',
                                              'autofill'  => true,
                                              'renameable' => true,
                                              'fullname'  => _('Department'),
                                              'onchange'  => $onchange);
                                } else if ($this->_locOverride) {
                                    $onchange = NULL;
                                    if (!util_isPlatformDisabled() && Pt_StandardUtil::autoFillRelated('location')) {
                                        $onchange = 'pt_editor_defaultRelated(this, null);';
                                    }

                                    $_params['columns'][$ckey]['_args'][] =
                                        array('path'      => 'LOCATION',
                                              'autofill'  => true,
                                              'renameable' => true,
                                              'fullname'  => _('Location'),
                                              'onchange'  => $onchange);
                                }

                                // if mcp is enabled uiprice field will be hidden
                                // hidden fields must be at bottom of all the visible fields
                                if ($this->_ismcpEnabled && $docpar['DISPLAY_BASECURRENCY'] != 'true') {
                                    $_params['columns'][$ckey]['_args'][] = $priceField;
                                }
                            }

                            if ($arg['path'] == 'UIVALUE') {
                                $valueField = $arg;

                                if ($this->_ismcpEnabled) {
                                    $_params['columns'][$ckey]['_args'][$akey]['totaled'] = false;
                                    $trxValue = array('path'              => 'TRX_VALUE',
                                                      'autofill'          => 1,
                                                      'totaled'           => 1,
                                                      'fullname'          => _('Extended price'),
                                                      'noJSErrValidation' => true);
                                    $_params['columns'][$ckey]['_args'][0] = $trxValue;

                                    if ($docpar['DISPLAY_BASECURRENCY'] == 'true') {
                                        $valueField['totaled'] = 0;
                                        $valueField['fullname'] = _('Extended base price');
                                        $_params['columns'][$ckey]['_args'][] = $valueField;
                                    }
                                }

                                if ($this->_deptOverride && $this->_locOverride) {
                                    $onchange = NULL;
                                    if (!util_isPlatformDisabled() && Pt_StandardUtil::autoFillRelated('location')) {
                                        $onchange = 'pt_editor_defaultRelated(this, null);';
                                    }

                                    $_params['columns'][$ckey]['_args'][] =
                                        array('path'      => 'LOCATION',
                                              'autofill'  => true,
                                              'renameable' => true,
                                              'fullname'  => _('Location'),
                                              'onchange'  => $onchange);
                                }

                                // if mcp is enabled uivalue field will be hidden
                                // hidden fields must be at bottom of all the visible fields
                                if ($this->_ismcpEnabled && $docpar['DISPLAY_BASECURRENCY'] != 'true') {
                                    $valueField['totaled'] = 0;
                                    $_params['columns'][$ckey]['_args'][] = $valueField;
                                }

                            }
                        }
                    }
                }
            }

        }

        return parent::MultilineLayout_Expand($_params);
    }


    /**
     * @param array $_params
     *
     * @return mixed
     */
    function MultilineLayout_Instantiate($_params)
    {

        $ret = Editor::MultilineLayout_Instantiate($_params);
        $multipleSrcDocText = ConversionManager::getmultipleSourceDocsText();

        if ($this->dt == BUILD_KIT || $this->dt == DIS_KIT) {
            $op = GetOperationId($this->mod . "/lists/stkitdocument/view");
        } else {
            $op = GetOperationId($this->mod . "/lists/" . $this->mod . "document/view");
        }

        $configOp = GetOperationId($this->mod . "/activities/" . $this->mod . "documentparams/view");

        if ($ret['path'] == 'HISTORY') {

            for ($i = 0; $i < count($ret['rows']); $i++) {
                $arow =& $ret['rows'][$i];

                for ($j = 0; $j < count($arow['cells']); $j++) {
                    $acell =& $arow['cells'][$j];

                    for ($k = 0; $k < count($acell['_args']); $k++) {

                        $aarg =& $acell['_args'][$k];
                        if ($aarg['path'] == 'DOCUMENTID' || $aarg['path'] == 'SOURCEDOCUMENTID') {
                            if ($aarg['value'] == $multipleSrcDocText) {
                                $aarg['onclick'] = "ShowSourceDocsMenu(this, 'SourceDocsMenu_History'); return false;";
                            } else {
                                $_sess = Session::getKey();
                                $url = 'editor.phtml?.sess=' . $_sess . '&.op=' . $op . '&.mod=' . $this->mod . '&.r=' . urlencode($aarg['value']) . '&.popup=1';
                                $aarg['onclick'] = "Launch('$url','mywindow','700','500');";
                                $aarg['statusmsg'] = "View document";
                            }
                            if ($aarg['path'] == 'DOCUMENTID') {
                                [$docid] = explode('-', $aarg['value']);
                            }
                        } elseif ($aarg['path'] == 'DOCCONFIG') {
                            $_sess = Session::getKey();
                            $url = 'editor.phtml?.sess=' . $_sess . '&.op=' . $configOp . '&.do=view&.mod=' . $this->mod . '&.r=' . urlencode($aarg['value']) . '&.popup=1';
                            $aarg['value'] = "Definition";
                            $aarg['onclick'] = "Launch('$url','mywindow','700','500');";
                            $aarg['statusmsg'] = "View Configuration";

                        }

                        if ($aarg['path'] == 'DOCSTATE') {
                            if ($this->dt == BUILD_KIT || $this->dt == DIS_KIT) {
                                /** @noinspection PhpUndefinedVariableInspection */
                                if ( $docid == BUILD_KIT && $aarg['value'] == 'Converted') {
                                    $aarg['value'] = 'Disassembled';
                                } elseif ($docid == BUILD_KIT && $aarg['value'] == 'Pending') {
                                    $aarg['value'] = 'Built';
                                } elseif ($docid == DIS_KIT && $aarg['value'] == 'Pending') {
                                    $aarg['value'] = 'Disassembled';
                                }
                            }
                        }
                    }
                }
            }
        }

        /* Adding Sales contract info, in the history tab, and showing it only if the document is having any contract info */
        $recurop = GetOperationId($this->mod . "/lists/" . $this->mod . "recurdocument/view");
        $docop = GetOperationId($this->mod . "/lists/" . $this->mod . "document");
        if ($ret['path'] == 'RECURHISTORY') {

            // Load detailed history data for display.
            $historyData = $this->GetHistoryData($ret);

            for ($i = 0; $i < count($ret['rows']); $i++) {
                $arow =& $ret['rows'][$i];

                for ($j = 0; $j < count($arow['cells']); $j++) {
                    $acell =& $arow['cells'][$j];

                    for ($k = 0; $k < count($acell['_args']); $k++) {

                        $aarg =& $acell['_args'][$k];

                        if ($aarg['path'] == 'RECURRECNO' && $aarg['value'] != '') {
                            $_sess = Session::getKey();
                            $url = 'editor.phtml?.sess=' . $_sess . '&.op=' . $recurop . '&.mod=' . $this->mod . '&.r=' . urlencode($aarg['value']) . '&.popup=1';
                            $aarg['onclick'] = "Launch('$url','mywindow','700','500');";
                            $aarg['statusmsg'] = "View document template";
                            $aarg['value'] = "Template";
                        }

                        if ($aarg['path'] == 'RECURTRANSACTION' && $aarg['value'] != '') {
                            $_sess = Session::getKey();
                            $url = 'lister.phtml?.sess=' . $_sess . '&.op=' . $docop . '&.schopkey=' . urlencode($aarg['value']) . '&.popup=1';
                            $aarg['onclick'] = "Launch('$url','mywindow','700','500');";
                            $aarg['statusmsg'] = "View document";
                            $aarg['value'] = "Transactions";
                        }

                        // Display detailed history data.
                        if ($aarg['path'] == 'LINENO' && $aarg['value'] == '') {
                            $aarg['value'] = $historyData[$i]['LINENO'];
                        }
                        if ($aarg['path'] == 'UIVALUE' && $aarg['value'] == '') {
                            $aarg['value'] = $historyData[$i]['UIVALUE'];
                        }

                    }
                }
            }
        }

        if ($ret['subtotal']) {

            for ($i = 0; $i < count($ret['rows']); $i++) {
                $arow =& $ret['rows'][$i];

                //unset line numbers
                $arow['cells'][0]['_args'][0]['_func'] = 'labels';
                $arow['cells'][0]['_args'][0]['value'] = '';
                $arow['cells'][0]['_args'][0]['readonly'] = 1;

                for ($j = 0; $j < count($arow['cells']); $j++) {
                    $acell =& $arow['cells'][$j];
                    for ($k = 0; $k < count($acell['_args']); $k++) {
                        $aarg =& $acell['_args'][$k];
                        if ($i == 0 || $i == count($ret['rows']) - 1) {
                            $aarg['readonly'] = 1;
                        } else {
                            if (!strcmp($aarg['path'], "PERCENTEDIT")) {
                                $this->SetPercentViewMode($arow, $aarg['value']);
                            }
                            if (!strcmp($aarg['path'], "ABSEDIT")) {
                                $this->SetAbsViewMode($arow, $aarg['value']);
                            }
                            if (!strcmp($aarg['path'], "TAXDETAIL") && $aarg['value']) {
                                $this->SetReadOnly($arow);
                            }
                        }
                    }
                }
            }
        }// End if
        return $ret;
    }


    /**
     * Returns an array containing the lineno/uivalue for each of the ui's history table rows.
     *
     * @access    private
     *
     * @param    array $values A set of the ui's history table data.
     *
     * @return    array containing the lineno/uivalue for each of the ui's history table rows.
     */
    function GetHistoryData($values)
    {
        global $gManagerFactory;
        $twoDHistory = array();
        $RecurdocMgr = $gManagerFactory->getManager('recurdocument');

        // For every row in the ui's history table, locate the recurDocEntryKey
        // and use it to load the lineno and uivalue from the database.
        for ($i = 0; $i < count($values['rows']); $i++) {
            for ($j = 0; $j < count($values['rows'][$i]['cells']); $j++) {
                if ($values['rows'][$i]['cells'][$j]['_args'][0]['path'] == 'RECURRECNO') {
                    $recurDocEntryKey = $values['rows'][$i]['cells'][$j]['_args'][0]['value'];
                    $twoDHistory[] = $RecurdocMgr->DoQuery('QRY_RECURDOCUMENT_GET_LINENO_AND_UIVALUE', array($recurDocEntryKey, $this->cny));
                }
            }
        }

        // Reformat the history data into a 1-dimensional format for display.
        $retVal = array();
        for ($i = 0; $i < count($twoDHistory); $i++) {
            for ($j = 0; $j < count($twoDHistory[$i]); $j++) {
                $retVal[] = $twoDHistory[$i][$j];
            }
        }
        return $retVal;
    }


    /**
     * @param array $arow
     *
     * @return array
     */
    function SetReadOnly(&$arow)
    {
        for ($j = 0; $j < count($arow['cells']); $j++) {
            $acell =& $arow['cells'][$j];
            for ($k = 0; $k < count($acell['_args']); $k++) {
                $aarg =& $acell['_args'][$k];
                $aarg['readonly'] = 1;
            }
        }
        return $arow;
    }

    /**
     * @param array  $arow
     * @param string $mode
     */
    function SetPercentViewMode(&$arow, $mode)
    {
        for ($j = 0; $j < count($arow['cells']); $j++) {
            $acell =& $arow['cells'][$j];
            for ($k = 0; $k < count($acell['_args']); $k++) {
                $aarg =& $acell['_args'][$k];
                if (!strcmp($aarg['path'], "PERCENTVAL")) {
                    if ($mode != '1') {
                        $aarg['readonly'] = 1;
                        if ($aarg['value'] == 0) {
                            $aarg['value'] = "";
                        }
                    }
                }
            }
        }
    }

    /**
     * @param array  $arow
     * @param string $mode
     *
     * @return array
     */
    function SetAbsViewMode(&$arow, $mode)
    {

        $flds = array("ABSVAL");
        if ($this->_ismcpEnabled) {
            array_push($flds, "TRX_ABSVAL");
        }

        for ($j = 0; $j < count($arow['cells']); $j++) {
            $acell =& $arow['cells'][$j];
            for ($k = 0; $k < count($acell['_args']); $k++) {
                $aarg =& $acell['_args'][$k];
                if (in_array($aarg['path'], $flds)) {
                    if ($mode != '1') {
                        $aarg['readonly'] = 1;
                        if ($aarg['value'] == 0) {
                            $aarg['value'] = "";
                        }
                    } elseif (!strcmp($aarg['path'], "ABSVAL") && ($this->_ismcpEnabled)) {
                        $aarg['readonly'] = 1;
                        if ($aarg['value'] == 0) {
                            $aarg['value'] = "";
                        }
                    }
                }
            }
        }
        return $arow;
    }

    /**
     * @param array $_params
     *
     * @return array
     */
    function Buttons_Instantiate($_params)
    {

        switch ($_params['state']) {
            case Editor_ShowNewState:
                $dobutton = _('Post');
                $doaction = 'create';
                $draftbutton = _('Draft & done');
                $draftaction = 'draftcreate';
                $scontinuebutton = _('Draft & continue');
                $scontinueaction = 'savecontinue';
                $saveandnewbutton = _('Post & new');
                $saveandnewaction = 'create';
                $cancelbutton = _('Cancel');
                $cancelaction = 'cancel';
                $deliverbutton = _('Print to...');
                $deliveraction = 'deliver';
                $submitbutton = _('Submit');
                $submitaction = 'createsubmit';
                break;
            case Editor_ShowEditState:
                $dobutton = _('Post');
                $doaction = 'save';
                $scontinuebutton = _('Post & continue');
                $scontinueaction = 'savecontinue';
                $draftbutton = _('Draft & done');
                $draftaction = 'draftsave';
                $cancelbutton = _('Cancel');
                $cancelaction = 'cancel';
                $deliverbutton = _('Print to...');
                $deliveraction = 'deliver';
                $submitbutton = _('Submit');
                $submitaction = 'editsubmit';
                break;
            case Editor_ShowViewState:
                $editbutton = _('Edit');
                $editaction = 'edit';
                $cancelbutton = _('Done');
                $cancelaction = 'cancel';
                $deliverbutton = _('Print to...');
                $deliveraction = 'deliver';
                break;
        }

        /** @noinspection PhpUndefinedVariableInspection */
        $_params['draftbutton'] = $draftbutton;
        /** @noinspection PhpUndefinedVariableInspection */
        $_params['draftaction'] = $draftaction;
        /** @noinspection PhpUndefinedVariableInspection */
        $_params['scontinuebutton'] = $scontinuebutton;
        /** @noinspection PhpUndefinedVariableInspection */
        $_params['scontinueaction'] = $scontinueaction;
        /** @noinspection PhpUndefinedVariableInspection */
        $_params['dobutton'] = $dobutton;
        /** @noinspection PhpUndefinedVariableInspection */
        $_params['doaction'] = $doaction;
        /** @noinspection PhpUndefinedVariableInspection */
        $_params['saveandnewbutton'] = $saveandnewbutton;
        /** @noinspection PhpUndefinedVariableInspection */
        $_params['saveandnewaction'] = $saveandnewaction;
        /** @noinspection PhpUndefinedVariableInspection */
        $_params['submitbutton'] = $submitbutton;
        /** @noinspection PhpUndefinedVariableInspection */
        $_params['submitaction'] = $submitaction;

        /** @noinspection PhpUndefinedVariableInspection */
        $_params['deliverbutton'] = $deliverbutton;
        /** @noinspection PhpUndefinedVariableInspection */
        $_params['deliveraction'] = $deliveraction;
        /** @noinspection PhpUndefinedVariableInspection */
        $_params['cancelbutton'] = $cancelbutton;
        /** @noinspection PhpUndefinedVariableInspection */
        $_params['cancelaction'] = $cancelaction;
        /** @noinspection PhpUndefinedVariableInspection */
        $_params['editbutton'] = $editbutton;
        /** @noinspection PhpUndefinedVariableInspection */
        $_params['editaction'] = $editaction;


        return $_params;
    }

    /**
     * @param array $_fields
     *
     * @return string
     */
    function GetNumOfRowsPath(&$_fields)
    {
        return "_$_fields[varname]_numofrows";
    }


    /**
     * @param array $_layout
     *
     * @return int
     */
    function FigureOutNumOfRows($_layout)
    {
        if ($_layout['path'] == 'SUBTOTALS') {
            $obj =& Request::$r->GetCurrentObject();
            $numOfRowsInTheInstance = count(EntityManager::AccessByPath($obj, $_layout['path']));
            //Picking up total no. of subtotal lines to be used later in Autofill() , for populating default dept and loc
            Request::$r->_subtotalCount = $numOfRowsInTheInstance;
            return $numOfRowsInTheInstance;
        } else {
            //use this to set the rowcount from the profile
            GetUserPreferences($upref);
            if (isset($upref['ROWCOUNT']) && $upref['ROWCOUNT'] != '') {
                $_layout['numofrows'] = $upref['ROWCOUNT'];
            }
            return Editor::FigureOutNumOfRows($_layout);
        }
    }

    /**
     * @param array $_field
     *
     * @throws Exception
     */
    function ShowSimpleFieldValue(&$_field)
    {

        global $kINVid;
        $multipleSrcDocText = ConversionManager::getmultipleSourceDocsText();

        if ($_field['hidden']) {
            echo("&nbsp;");
            return;
        }

        if ($_field['path'] == 'UIPRICE') {
            if ($this->state != 'showview') {
                $_field['assists'][] = array(
                    'customlink' => "SuggestPriceClick('" . $_field['layer'] . "','" . $_field['form'] . "','" . $_field['rownum'] . "');",
                    'text'       => 'suggest',
                    'statusmsg'  => "Suggest Price",
                );
            }
        }
        if ($_field['path'] == 'AVAILLINK' && IsInstalled($kINVid)) {
            $_field['onclick'] = "javascript: if (this.disabled) return false; AvailableClick('" . $_field['layer'] . "','" . $_field['form'] . "','" . $_field['rownum'] . "');";

        }


        if ($_field['path'] == 'PICKLIST' && IsInstalled($kINVid)) {

            $_field['onclick'] = "javascript: if (this.disabled) return false; PickListReport('" . $_field['layer'] . "','" . $_field['form'] . "','" . $_field['rownum'] . "');";

        }

        /* Add a new link in line entries to drill down to inventory costing report, which shows the distribution of cost for this line entry */
        if ($_field['path'] == 'COSTLINK' && IsInstalled($kINVid)) {
            $_field['onclick'] = "javascript: if (this.disabled) return false; CostReportClick('" . $_field['layer'] . "','" . $_field['form'] . "','" . $_field['rownum'] . "');";
        }

        if ($_field['path'] == 'SLBINFO' && IsInstalled($kINVid)) {
            $_field['onclick'] = "javascript: if (this.disabled) return false; SLBInfoClick('" . $_field['layer'] . "','" . $_field['form'] . "','" . $_field['rownum'] . "');";

        }

        if ($_field['path'] == 'HDRPICKLINK' && IsInstalled($kINVid)) {

            $_field['onclick'] = "javascript: if (this.disabled) return false; HdrPickListReport('" . $_field['layer'] . "','" . $_field['form'] . "','" . $_field['rownum'] . "');";

        }

        if ($_field['path'] == 'RECURRINGSCHEDULE') {
            global $gManagerFactory;
            $_sess = Session::getKey();

            $r = Request::$r->_r;
            $doctype = Request::$r->_dt;

            $recurdocMgr = $gManagerFactory->getManager('recurdocument');
            $result = $recurdocMgr->DoQuery('QRY_RECURDOCUMENT_GET_TEMPLATEID', array($r));
            $docid = $result[0]['DOCID'];

            if (isset($docid) && $docid != '') {
                $op = GetOperationId($this->mod . "/lists/" . $this->mod . "recurdocument/view");

                $url = 'editor.phtml?.sess=' . $_sess . '&.op=' . $op . '&.mod=' . $this->mod . '&.r=' . urlencode($docid) . '&.dt=' . urlencode($doctype) . '&.popup=1&.viewsch=T';
                $_field['onclick'] = "Launch('$url','mywindow','700','500');";
                $_field['statusmsg'] = "View Recurring Schedule";
                $_field['href'] = "View Recurring Schedule";
            } else {
                $_field['hreftxt'] = "";
            }
        }

        if ($_field['path'] == 'UIQTY') {
            $_field['onchange'] = "DisallowNegativeQtyForSerializedItems('" . $_field['layer'] . "','" . $_field['form'] . "','" . $_field['rownum'] . "',this);";
        }

        $recalledID = Request::$r->_r;

        $AutoFillArray = array('VIRTUAL.CUSTVENDID', 'VIRTUAL.WHENCREATED', 'VIRTUAL.DOCPARID', 'VIRTUAL.DOCNO');
        if (($this->state == 'showedit' || $this->state == 'showview') && $_field['path'] == 'CREATEDFROM' && $_field['value'] == $multipleSrcDocText) {
            $_field['type'] = array(
                'ptype'            => 'href',
                'type'             => 'href',
                'size'             => 60,
                'maxlength'        => 60,
                'multilinecolsepr' => 25,
                'format'           => '/^[\w\s_\-]{1,60}$/',
            );
            $_field['onclick'] = "ShowSourceDocsMenu(this, 'SourceDocsMenu_Header'); return false;";
            $this->ShowSourceDocumentMenu("SourceDocsMenu_Header");
        }
        if ($this->state == 'shownew' && $_field['path'] == 'CREATEDFROM' && !$recalledID) {
            if ($_field['value'] == $multipleSrcDocText) {

                $_field['type'] = array(
                    'ptype'            => 'href',
                    'type'             => 'href',
                    'size'             => 60,
                    'maxlength'        => 60,
                    'multilinecolsepr' => 25,
                    'format'           => '/^[\w\s_\-]{1,60}$/',
                );
                $_field['onclick'] = "ShowSourceDocsMenu(this, 'SourceDocsMenu_Header'); return false;";
                $this->ShowSourceDocumentMenu("SourceDocsMenu_Header");

                Editor::ShowSimpleFieldValue($_field);
            } else {
                $this->ShowExpandedConvertedFrom($_field);
            }
        } elseif ($this->state == 'shownew' && in_array($_field['path'], $AutoFillArray)) {
            $this->ShowTaggedFieldValue($_field);
        } else if ($this->state != 'shownew' && $_field['path'] == 'DOCPARID' || $_field['path'] == 'VIRTUAL.DOCPARID') {
            $this->ShowConvertCopyControl($_field);
        } elseif ($this->state == 'showedit' && $_field['path'] == 'VIRTUAL.WHENCREATED') {
            $this->ShowTaggedFieldValue($_field);
        } else {
            if ($this->state == 'shownew' && $_field['path'] == 'DOCNO' && ($_field['readonly'] == false)) { ?>
                <table border=0 cellspacing=0>
                    <tr>
                        <td>
                            <?
                            Editor::ShowSimpleFieldValue($_field); ?>
                        </td>
                    </tr>
                    <tr>
                        <td valign="top" nowrap colspan="2" class="value_cell"><font id="dupdocno"
                                                                                     style=" visibility:hidden; display:none;  color:red; background-color:#FFFFCC; border-style=solid; border-width=1px; border-color=#999999">
                                Warning! Document Number already used. </font></td>
                    </tr>
                </table>
                <?
            } else {
                Editor::ShowSimpleFieldValue($_field);
            }
        }


        if ($_field['path'] == 'DUMMYSOURCEMENU') {
            $this->ShowSourceDocumentMenu('SourceDocsMenu_History');
        }
    }


    /**
     * @param array $_params
     *
     * @return bool
     * @throws Exception
     */
    function ProcessEditAction(&$_params)
    {
        //	eppp_p($_params);
        global $gManagerFactory;
        $entityMgr = $this->GetManager($_params['entity']);

        $docpar = $this->GetBaseDocPar();

        if ($this->ProcessErrorRetrivalAction($entityMgr)) {
            return true;
        }
        Request::$r->_changed = false;

        $obj = Request::$r->GetCurrentObject();
        if (empty($obj) || $obj == '') {
            $objId = Request::$r->{Globals::$g->kId};
            $obj = $this->getEntityData($_params['entity'], $objId);
        }

        $this->EditorGetSubTotals($_params, $obj, false);

        if ('' === $docpar['ALLOWEDITBILLTO'] || 'false' === $docpar['ALLOWEDITBILLTO']) {
            $this->MatchTemplates($_params['layout']['pages'][0], array('path' => 'BILLTO.CONTACTNAME'), $billtoarr);
            foreach ( $billtoarr as $i => $x) {
                $billtoarr[$i]['readonly'] = 1;
            }
        }
        if ('' === $docpar['ALLOWEDITSHIPTO'] || 'false' === $docpar['ALLOWEDITSHIPTO']) {
            $this->MatchTemplates($_params['layout']['pages'][0], array('path' => 'SHIPTO.CONTACTNAME'), $shiptoarr);
            foreach ( $shiptoarr as $i => $x) {
                $shiptoarr[$i]['readonly'] = 1;
            }
        }

        for ($i = 0; $i < count($obj['ENTRIES']); $i++) {
            if (isset($obj['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO'])) {
                if (isset($obj['ENTRIES'][$i]['WAREHOUSE']['NAME'])) {
                    $obj['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO'] = $obj['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO'] . '--' . $obj['ENTRIES'][$i]['WAREHOUSE']['NAME'];
                }
            }
        }
        if (empty($obj)) {
            global $gErr;
            $entityDesc = $_params['entityDesc'];
            /** @noinspection PhpUndefinedVariableInspection */
            $gErr->addError("BL03000021", __FILE__ . ":" . __LINE__, _("Cannot access $entityDesc '$objId'."));
            $this->state = $this->kErrorState;
        } else {
            global $kSOid, $kPOid, $kINVid;
            $modArray = array('so' => $kSOid, 'po' => $kPOid, 'inv' => $kINVid);
            $precisionFields = array('so' => 'NUMDEC_SALE', 'po' => 'NUMDEC_PUR', 'inv' => 'NUMDEC_STD');
            $itemMgr = $gManagerFactory->getManager('item');

            GetModulePreferences($modArray[$this->mod], $prefs);
            $appPrecision = ($prefs['ITEMPRECISION']) ?: 2;

            $itemsArr = array();
            foreach ( $obj['ENTRIES'] as $entry) {
                [$itemid] = explode('--', $entry['ITEMID']);
                $itemsArr[] = $itemid;
            }

            //$uomInfoCache = $itemMgr->GetUOMPrecissionInfo($itemsArr);
            $itemidAsKey = true;
            $uomInfoVals = $itemMgr->GetUOMInfoCache($itemsArr, $itemidAsKey);

            foreach ($obj['ENTRIES'] as $key => $entry) {

                if ($entry['ITEM'][$precisionFields[$this->mod]] != '') {
                    $itemPrecision = $entry['ITEM'][$precisionFields[$this->mod]];
                } else {
                    $itemPrecision = $appPrecision;
                }
                $itemMgr->GetLineEntry_UOMPrecissionInfo($entry, $uomInfoVals, $conversion, $uomPrecission);
                $obj['ENTRIES'][$key]['QTY_CONVERTED'] = ibcdiv($entry['QTY_CONVERTED'], $conversion, $uomPrecission, true);
                $obj['ENTRIES'][$key]['RETAILPRICE'] = ibcmul($obj['ENTRIES'][$key]['RETAILPRICE'], $conversion, $itemPrecision, false);
            }

            Request::$r->SetCurrentObject($obj);
            $this->state = $this->CalcEditorState($entityMgr);
            //$this->state = $this->kShowEditState;
        }
        return true;
    }

    /**
     * @param string $menuID
     */
    function ShowSourceDocumentMenu($menuID)
    {
        ?>
        <DIV ID="<?= $menuID ?>" class="Result2"
             STYLE="position: absolute;visibility: hidden;background-color: white;layer-background-color: white;border: 2px outset white;"
             ONMOUSEOVER="onMousedLayer = 'set';clearTimeout(this.tid);"
             ONMOUSEOUT="menu = this; onMousedLayer=''; this.tid = setTimeout ('hideSourceDocsMenu(\'<?= $menuID ?>\')', 100);"></DIV>
        <?
    }

    /**
     * @param string[] $_field
     */
    function ShowConvertCopyControl(&$_field)
    {
        $doctype = $_field['value'];

        ?>
        <DIV ID="convertMenu<?= $_field['layer'] ?>" class="Result2"
             STYLE="position: absolute;
                  visibility: hidden;
                  background-color: white;
                  layer-background-color: white;
                  border: 2px outset white;"
             ONMOUSEOUT="menu = this; onMousedLayer=''; this.tid = setTimeout ('hideMenu()', 100);"
             ONMOUSEOVER="onMousedLayer = 'set'; clearTimeout(this.tid);">
        </DIV>
        <TABLE cellpadding="0" cellspacing="0" border="0">
            <TR>
                <TD valign="middle" nowrap>
                    <INPUT type="hidden" name="<?= $_field['varname'] ?>" value="<?= $doctype ?>">
                    <font face="Verdana, Arial, Helvetica">
                        <b><? echo $doctype; ?>&nbsp;</b>
                    </font>
                </TD>
                <?
                if (!($doctype == BUILD_KIT || $doctype == DIS_KIT)) { // do not include build kits and disassemble kits TD in the list --mmahur
                    ?>

                    <TD valign="middle">
                        <? if (IsMultiEntityCompany() && GetContextLocation()) { ?>
                            <? if ($this->_docIsOwned) { ?>
                                <? if (!$this->_noConvertLink) { ?>
                                    <a class="Pick" href="#"
                                       onClick="showMenu(event, '<?= $doctype ?>', '<?= $_field['layer'] ?>', this, 'Update'); return false;"
                                       onmouseover='window.status="Convert To";return true;'
                                       onmouseout='setTimeout("hideMenu()", 100);window.status=""; return true;'>convert</a>
                                    <BR>
                                    <?
                                } ?>
                                <?
                            } ?>
                            <?
                        } else { ?>
                            <? if (!$this->_noConvertLink) { ?>
                                <a class="Pick" href="#"
                                   onClick="showMenu(event, '<?= $doctype ?>', '<?= $_field['layer'] ?>', this, 'Update'); return false;"
                                   onmouseover='window.status="Convert To";return true;'
                                   onmouseout='setTimeout("hideMenu()", 100);window.status=""; return true;'>convert</a>
                                <BR>
                                <?
                            } ?>
                            <?
                        } ?>
                        <a class="Pick" href="#"
                           onClick="showMenu(event, '<?= $doctype ?>', '<?= $_field['layer'] ?>', this, 'Copy'); return false;"
                           onmouseover='window.status="Copy To";return true;'
                           onmouseout='setTimeout("hideMenu()", 100); window.status=""; return true;'>copy</a><BR>
                    </TD>
                    <?
                } ?>
            </TR>
        </TABLE>
        <?
    }

    /**
     * @param string[] $_field
     * @param bool     $_inlineitem
     * @param bool     $encodeLabel
     */
    function ShowSimpleFieldLabel(&$_field, $_inlineitem = false, $encodeLabel = true)
    {
        if ($this->state == 'shownew' && $_field['path'] == 'WHENDUE') {
            ?> <FONT id=<? echo $_field['path'] . 'Label'; ?> class="form_required">*<?
            echo $_field['fullname'];
            ?>&nbsp;</FONT><?
        } else {
            Editor::ShowSimpleFieldLabel($_field, $_inlineitem);
        }
    }


    //Turn off the deliver button should we allow printing of documents without invoice numbers?
    function ShowNew()
    {
        unset($this->_params['buttons']['deliverbutton']);
        $this->ShowTop();
    }

    /**
     * @param string $docid
     *
     * @return false|string[][]
     */
    function GetSourceDocs($docid)
    {
        $cny = GetMyCompany();
        $qry = "SELECT unique sourcedocument.docid
          FROM docentry,
               dochdrmst document,
               dochdrmst sourcedocument
         WHERE (document.docid = :1)
           AND docentry.dochdrkey = document.record#(+)
           AND document.cny#(+) = :2
           AND docentry.source_dockey = sourcedocument.record#(+)
           AND sourcedocument.cny#(+) = :2
           AND docentry.cny#(+) = :2";

        $result = QueryResult(array($qry, $docid, $cny));

        return $result;
    }


    /**
     *  Add Javascript and CSS to the page.  Subclasses really should call back to their parent.
     *
     * @param bool $addYuiCss include the YUI css files
     *
     * @throws Exception
     */
    function showScripts($addYuiCss = true)
    {
        parent::showScripts($addYuiCss);
        global $gManagerFactory, $gWarnOnSaveNoCheckJS;
        $_sess = Session::getKey();
        $copy = Request::$r->_copymode;

        $docparMgr = $gManagerFactory->getManager('documentparams');
        $baseCurrency = GetBaseCurrency();

        $r = Request::$r->_r;
        $opid = GetOperationId($this->mod . '/lists/' . $this->mod . 'document/create');

        // in edit mode get the source documents if the document is converted by multiple documents
        $sourceDocs = $this->GetSourceDocs($r);
        foreach ($sourceDocs as $sDoc) {
            $sDocs[] = "['" . addslashes($sDoc['DOCID']) . "']";
        }
        $sourceDocsjs = '[' . (isset($sDocs) ? join(',', $sDocs) : '') . ']';

        // to get the in/out , to be passed to slbinfoclick function
        $docpar = $this->GetBaseDocPar();

        $isReturn = isReturnDocument($docpar);

        $parentid = GetParentID($r, $copy, $isReturn);

        $obj = Request::$r->GetCurrentObject();

        $isBackOrder = false;
        if ($this->do == 'edit' || $this->do == 'view') {
            $docid = $r;

            if ($obj['BACKORDER'] == 'Yes') {
                $isBackOrder = true;
            }
        } else {
            $docid = '';
        }
        $modArray = array('so' => 'S', 'po' => 'P', 'inv' => 'I');
        $spi = $modArray[$this->mod];


        $overrideExchRateType = $docpar['OVERRIDE_EXCH_RATE_TYPE'];
        $in_out = $docpar['IN_OUT'];
        $docparRecno = $docpar['RECORDNO'];
        $enablerevrec = $docpar['ENABLEREVREC'];
        $renewalsEnabled = $docpar['ENABLERENEWALS'];
        $enableoverridetax = $docpar['ENABLEOVERRIDETAX'];

        // Used for revrec fetch
        $opIdForSoDocumentEditor = GetOperationId('so/activities/sodocument/create');

        //check whether this is a Transafer In document
        if (in_array($docpar['DOCID'], array('Build Kits', 'Disassemble Kits'))) { //Checking for transfer in is not valid for Build Kits and Disassemble Kits -- mmahur
            $transferin = false;
            $transferout = false;
        } else {
            if ($this->mod == 'inv' && ($docpar['UPDATES_INV'] == 'Value' || $docpar['UPDATES_INV'] == 'Quantity and Value')) {
                if ($docpar['IN_OUT'] == 'Increase') {
                    $transferin = true;
                } else if ($docpar['IN_OUT'] == 'Decrease') {
                    $transferout = true;
                }
            }
        }

        $UICacheObjects = GetCacheObjectsForUIValidation($this->mod, $spi, $obj);

        $js_terms = str_replace('\'', '\\u0027', (Util_DataRecordFormatter::phpToJson($UICacheObjects['TERM'])));

        $js_uoms = str_replace('\'', '\\u0027', (Util_DataRecordFormatter::phpToJson($UICacheObjects['UOM'])));

        // Get recall info
        if ($this->state != 'shownew') {

            global $_userid;
            $ddlist = $completeList = array($this->dt);
            $arrExplode = explode('@', $_userid);
            $userkey = array_shift($arrExplode);
            $allowedDocs = $docparMgr->DoQuery('QRY_DOCUMENTPARAMS_ALLOWED_RECALL_TO', array($spi, 'T', $this->dt));
            $allowedDocs = upermFilterResult($allowedDocs, $userkey);
            $allowedDocs = filterDocsForUserType($allowedDocs);
            foreach ($allowedDocs as $doc) {
                $ddlist[] = str_replace("'", "\'", $doc['DOCID']);
            }

            $docs = GetDocumentMenuList($this->mod);
            foreach ($docs as $doc) {
                if (!in_array($doc['DOCID'], array(BUILD_KIT, DIS_KIT))) { // do not include build kits and disassemble kits TD in the list --mmahur
                    $completeList[] = str_replace("'", "\'", $doc['DOCID']);
                }
            }
        }
        /** @noinspection PhpUndefinedVariableInspection */
        $js_doctypes = "[['" . join("', '", $ddlist) . "']]";
        /** @noinspection PhpUndefinedVariableInspection */
        $js_doctypesFull = "[['" . join("', '", $completeList) . "']]";

        $docparjs = str_replace('\'', '\\u0027', (Util_DataRecordFormatter::phpToJson($UICacheObjects['DOCPAR'])));

        // Fime Me: Use the JS version instead
        include_once 'js_dates.inc';
        showJsDates();

        //	Get the Fractional Precision related info here
        $appPrecision = $this->LookupAppPrecision();

        $shouldProrate = 'false';
        $IsComingFromSFDC = (Profile::hasProperty('SFORCEKEY') && Profile::getProperty('SFORCEKEY') != '') ? true : false;

        if ($docpar['OVERRIDE_PRICE'] == 'true') {
            if ($IsComingFromSFDC) {
                $SFDCPrefMgr = $gManagerFactory->getManager('sforcesetup');
                $SFDCPref = $SFDCPrefMgr->get('');
                if ($SFDCPref['SFORCEPRICINGOPT'] == 'I') {
                    $shouldProrate = 'true';
                }
            } else {
                $shouldProrate = 'true';
            }
        }

        GetModulePreferences('7.INV', $invprefs);
        $defaultUOMGrp = $invprefs['DEFAULT_UOMGRP'];

        GetUserPreferences($upref);
        $upref_docpar_whse = $upref['DEFAULT_WAREHOUSE'];
        if ($upref_docpar_whse == '' && $docpar['DEFAULT_WAREHOUSE'] != '') {
            $upref_docpar_whse = $docpar['DEFAULT_WAREHOUSE'];
        }

        GetModulePreferences('8.SO', $prefs);
        $isLineDiscountOnSuggestedPrice = $prefs['PRICING.LINEDISCOUNTONSUGGESTEDPRICE'];
        // Used for title
        $dict = Dictionary::getInstance();
        if ($this->mod == 'po') {
            $mvcheck = 'vendor';
            $title = $dict->GetRenamedText(_('Vendor'));
            $objop = GetOperationId('ar/lists/vendor');
        } elseif ($this->mod == 'so') {
            $mvcheck = 'customer';
            $title = $dict->GetRenamedText('Customer');
            $objop = GetOperationId('ar/lists/customer');
        }
        /** @noinspection PhpUndefinedVariableInspection */
        if ( $mvcheck != '' && IsMultiVisibilitySubscribed($mvcheck)) {
            $multivisibility = true;
            ?>
            <script src="../resources/js/mvdocument.js"></script>
            <?
        } ?>

        <? if ($this->_ismcpEnabled) { ?>
        <script src="../resources/js/mcdoceditor.js"></script>
        <?
    } ?>
        <script src="../resources/js/polyfill/promise.js"></script>
        <script src="../resources/js/qrequest.js"></script>
        <script src="../resources/js/json2.js"></script>
        <SCRIPT language=javascript>
            <!--
            var enableCalculate = true;
            var discountProratePrice = new Array();
            var isLineDiscountOnSuggestedPrice = '<?echo $isLineDiscountOnSuggestedPrice;?>';
            var sfdcpricing = <? echo $this->sfdcPricing ?? 'false';  ?>;
            var copymode = '<?echo $copy;?>';
            var datefmt = '<? echo GetUserDateFormat(); ?>';
            var mod = '<?= $this->mod ?>';
            var uom_arr = <?echo $js_uoms;?>;
            var term_arr = <?echo $js_terms;?>;
            var app_precision = <? echo $appPrecision; ?>;
            var projectop = "<? echo GetOperationId('ar/lists/project'); ?>";
            var restrictproject = <? echo((IADimensions::IsDimensionEnabled('so', 'project')) ? 'true' : 'false'); ?>;

            var menu;
            var doctypes = <?echo $js_doctypes;?>;
            var doctypesCopy = <?echo $js_doctypesFull;?>;
            var sess = escape('<?echo $_sess;?>');
            var op = '<?echo $opid;?>';
            var docid = '<?echo addslashes($r);?>';
            var overrideExchRateType = '<?echo $overrideExchRateType;?>';
            var newdocid = '<?echo addslashes($docid);?>';
            var parentid = '<?echo addslashes($parentid);?>';
            var docmode = '<?echo $this->do;?>';
            var docparRecno = '<? echo $docparRecno;?>';
            var docparamsArr = <?echo $docparjs;?>;
            var done = '<?echo insertDoneUnEnc(Request::$r->_done);?>';
            var priceFetchDisabled = <?=$this->priceFetchDisabled?>;

            var tocheck = '<? echo $this->_params['entity']; ?>';
            var creditlimitcheck = '<? echo GetCreditLimitCheck(); ?>';
            var onholdcheck = '<? echo GetOnHoldCheck(); ?>';
            var crlimit = '';
            var entitydue = '';

            if ('<?echo $IsComingFromSFDC;?>') {
                crlimit = '<? echo $this->sfcrlimit; ?>';
                entitydue = '<? echo $this->sftotdue; ?>';
            }
            var in_out = '<?echo $in_out;?>';
            var ismcpEnabled = '<? echo $this->_ismcpEnabled; ?>';
            var baseCurrency = '<? echo $baseCurrency; ?>';
            var shouldProrate = '<?echo $shouldProrate;?>';
            var transferin = '<?/** @noinspection PhpUndefinedVariableInspection */echo $transferin;?>';
            var transferout = '<?/** @noinspection PhpUndefinedVariableInspection */echo $transferout;?>';
            var isReturn = '<?echo $isReturn;?>';
            var isBackOrder = '<?echo $isBackOrder;?>';

            var enableoverridetax = '<?=$enableoverridetax?>';
            if (copymode != 'Update') {
                var sourceDocsArr = <?echo $sourceDocsjs;?>;
            }
            var wareselmethod = '<?echo $docpar['WAREHOUSESELMETHOD'];?>';
            var atlas = '<?echo $this->atlas;?>';

            var upref_docpar_whse = '<? echo addslashes($upref_docpar_whse);?>';
            var invTransOutWarn = '<? echo Request::$r->_invTransOutWarn?>';
            //		var recalled = '<?echo Request::$r->_r;?>';

            var dt = "<?echo $this->dt;?>";
            var max_dummyid = "<?echo MAX_DUMMY_ID;?>";

            // Used for AutoPopulateCustVendID() function.
            var bt = '<? echo $docpar['ALLOWEDITBILLTO'] ?>';
            var st = '<? echo $docpar['ALLOWEDITSHIPTO'] ?>';

            // For PODocumentOnLoad/SODocumentOnLoad
            var multivisibility = <? /** @noinspection PhpUndefinedVariableInspection */echo(($multivisibility) ? 'true' : 'false'); ?>;
            var objop = "<? /** @noinspection PhpUndefinedVariableInspection */echo($objop); ?>";


            var custvendTitle = '<?/** @noinspection PhpUndefinedVariableInspection */echo $title;?>';
            var qop = "<? echo GetOperationId('co/lists/exchangerate/view'); ?>";
            var docviewop = "<? echo GetOperationId($this->mod . '/lists/' . $this->mod . 'document/view'); ?>";

            function WarnOnSaveDocument() {    <? echo $gWarnOnSaveNoCheckJS; ?> }

            // Used for AutoPopulateCustVendID() function ends.

            //For AvailableClick
            var invstatusop = "<? echo GetOperationId('inv/reports/invstatus'); ?>";

            //For PickListReport
            var phyinventoryop = "<? echo GetOperationId('inv/reports/physicalinventory'); ?>";

            //For HdrPickListReport
            var pickinglistop = "<? echo GetOperationId('so/reports/pickinglist'); ?>";

            //For CostReportClick
            var itemcogsop = "<? echo GetOperationId('inv/reports/itemcogs'); ?>";

            //For SLBInfoClick
            var docentrytrackop = "<? echo GetOperationId($this->mod . '/lists/documententrytrack/create'); ?>";
            var docentrytrackkitop = "<? echo GetOperationId('so/lists/documententrytrackkit/create'); ?>";

            //For RespProcesser_ItemID
            var renewalsEnabled = <? echo(($renewalsEnabled) ? 'true' : 'false'); ?>;
            var itemsHaveStartEndDate = <? echo(($this->itemsHaveStartEndDate) ? 'true' : 'false'); ?>;
            var fetchRenewalTermurl = '<? echo "editor.phtml?.op=$opIdForSoDocumentEditor&.sess=$_sess&_state=init&.action=fetchtermenddate"; ?>';

            //For RespProcesser_ProratePrice
            var fetchproratepriceURL = '<? echo "editor.phtml?.op=$opIdForSoDocumentEditor&.sess=$_sess&_state=init&.action=fetchprorateprice"; ?>';

            var enablerevrec = '<? echo $enablerevrec; ?>';
            var fetchdefaultrevrectemplateURL = '<? echo "editor.phtml?.op=$opIdForSoDocumentEditor&.sess=$_sess&_state=init&.action=fetchdefaultrevrectemplate"; ?>';

            var defaultuomgrp = '<?= $defaultUOMGrp; ?>';

            // This is needed to implement some recur document validations in the documenteditor.js
            var fromRecurDocument = false;

            var qtydensearr = '';
            // -->
        </SCRIPT>
        <? $this->LoadJSObjectArrays($docpar); ?>
        <script src="../resources/js/documenteditor.js"></script>
        <script src="../resources/js/apar.js"></script>
        <?

    }


    /**
     * @param string[] $docpar
     */
    function LoadJSObjectArrays($docpar)
    {
        //if ($this->state == 'showview') return;

        // NEW
        StartTimer("COLLECT");
        $item_whse_data = $this->CollectAutoFillData($docpar);

        $item_data = $item_whse_data['ITEMS'];
        $whse_data = $item_whse_data['WHSES'];
        //$qty_data = $item_whse_data['QTYS'];

        // ENDNEW

        //$items = '['.join(',',$item_data).']';
        $items = $item_data;

        // NEW
        $delim = '';
        $whses = "[";
        for ($k = 0; $k < count($whse_data); $k++) {
            $whseName = util_encode(str_replace("'", "\'", $whse_data[$k]['NAME']));
            $whses = $whses . $delim . "'" . util_encode(str_replace("'", "\'", $whse_data[$k]['LOCATION_NO'])) . "--" . $whseName . "'";
            $delim = ',';
        }
        $whses = $whses . "]";

        $js_whses = "<SCRIPT> whsedensearr = " . $whses . "; </SCRIPT>";
        //$js_qtys= "<SCRIPT> qtydensearr = ".$qtys."; </SCRIPT>";
        // ENDNEW
        $js_items = "<SCRIPT> itemdensearr = " . $items . "; </SCRIPT>";

        echo $js_items;
        echo $js_whses;
        /** @noinspection PhpUndefinedVariableInspection */
        echo $js_qtys;
    }


    /**
     *            This function will refresh the caller window and close the current popup window.
     *            this behavoiur is mainly for convert link in a mega companies non-owned document.
     *            If there exeists a case where we need to not do this behaviour for popping document editor
     *            we will have to change this function.
     *
     * @access public
     */
    function ShowPopupClose()
    {
        ?>
        <HTML>
        <? $this->showScripts(); ?>
        <BODY onload="if ( window.opener ) { window.opener.location.reload(); } window.close();"></BODY>
        </HTML>
        <?
    }


    /**
     * @param array $_params
     *
     * @throws Exception
     */
    function FetchDefaultRevRecTemplate(/** @noinspection PhpUnusedParameterInspection */ &$_params)
    {
        $itemlabel = Request::$r->itemlabel;

        global $gManagerFactory;
        /** @var ItemManager $itemMgr */
        $itemMgr = $gManagerFactory->getManager('item');
        /** @var ItemGroupManager $itemglgrpMgr */
        $itemglgrpMgr = $gManagerFactory->getManager('itemglgroup');

        $itemObj = $itemMgr->Get($itemlabel);
        //echo($itemObj['GLGRPKEY']);
        //eppp_p($itemObj);
        if ($itemObj['ITEMTYPE'] == 'Kit' && $itemObj['REVPOSTING'] == 'Component Level') {
            echo('Use Kit Revenue Rules');
        } else {
            $itemglgrpObj = $itemglgrpMgr->Get($itemObj['GLGROUP']);
            echo($itemglgrpObj['REVRECTEMPLID']);
        }
        //eppp_p($itemglgrpObj['REVRECTEMPLID']);
        //dieFL();

        exit;
    }


    /**
     * @param array $_params
     */
    function ProcessRefreshAction(&$_params)
    {
        //$dt = Request::$r->_dt;
        $obj =& Request::$r->GetCurrentObject();
        $action = Request::$r->{$this->kAction};

        $obj = $this->DoRefreshAction($_params, $obj);
        $this->EditorGetSubTotals($_params, $obj, true);

        if ($this->state != $this->kErrorState) {
            Request::$r->SetCurrentObject($obj);
            Request::$r->$action = NULL;
        }
    }


    /**
     * @param array $_params
     * @param array $obj
     *
     * @throws Exception
     */
    function SetOverrideTax(&$_params, &$obj)
    {
        //eppp_p("SetOverrideTax");
        //eppp_p($_params);
        //eppp_p($obj);
        //eppp_p($GLOBALS['_POST']);
        //dieFL();
        global $gManagerFactory;

        //eppp_p($mod);

        $shiptoname = $obj['SHIPTO']['CONTACTNAME'];
        //eppp_p("shiptoname:".$shiptoname);

        $contactMgr = $gManagerFactory->getManager('contact');
        $shiptoraw = $contactMgr->GetRaw($shiptoname);
        $shiptoraw = $shiptoraw[0];

        $shiptotaxable = $shiptoraw['TAXABLE'];
        $shiptotaxgroupkey = $shiptoraw['TAXGROUPKEY'];
        //eppp_p("shiptotaxable:".$shiptotaxable);
        //eppp_p("shiptotaxgroupkey:".$shiptotaxgroupkey);

        $docparkey = $obj['_DOCPAR']['RECORDNO'];
        //eppp_p("docparkey:".$docparkey);

        $entries = &$obj['ENTRIES'];
        //eppp_p($entries);

        $this->MatchTemplates($_params, array('path' => 'OVERRIDETAX'), $alloverridetax);
        //eppp_p($alloverridetax);
        //dieFL();

        $entryCnt = count($entries);

        $itemMgr = $gManagerFactory->getManager('item');

        $itemsArr = array();
        for ($j = 0; $j < $entryCnt; $j++) {
            if ($entries[$j]['ITEMID'] != '') {
                [$itemid] = explode('--', $entries[$j]['ITEMID']);
                if (!in_array($itemid, $itemsArr)) {
                    $itemsArr[] = $itemid;
                }
            }
        }

        $itemRawCache = $itemMgr->GetItemsRawCache($itemsArr);

        for ($j = 0; $j < $entryCnt; $j++) {
            //eppp_p("ITEMID:".$entries[$j]['ITEMID']);

            $taxcapable = false;
            if ($entries[$j]['ITEMID'] != '') {
                [$itemid] = explode('--', $entries[$j]['ITEMID']);

                if ($itemRawCache[$itemid] != '') {
                    $itemtaxgroupkey = $itemRawCache[$itemid]['TAXGROUPKEY'];

                    $taxcapable = $itemMgr->IsTaxCapable(
                        $this->mod, $docparkey, $itemtaxgroupkey,
                        $shiptotaxable, $shiptotaxgroupkey
                    );
                }
            }

            //eppp_p($entries[$j]);
            //eppp_p($alloverridetax[$j]);
            //eppp_p("taxcapable:".$taxcapable);
            //eppp_p("j:".$j);

            if ($taxcapable) {
                // Enable control
                $alloverridetax[$j]['disabled'] = false;

                // Let the form value go unchanged
            } else {
                // Disable control
                $alloverridetax[$j]['disabled'] = true;
                $alloverridetax[$j]['value'] = 'false';

                // Reset form value
                $entries[$j]['OVERRIDETAX'] = 'false';
            }
            //eppp_p($alloverridetax[$j]);
        }
        //eppp_p($_params);
        //dieFL();
    }

    /**
     * @param array  $_fields
     * @param string $_pos
     *
     * @throws Exception
     */
    function ShowMultilineRefresh(&$_fields, $_pos)
    {
        //eppp_p('ShowMultilineRefresh');
        //eppp_p($_fields['rows']);
        //eppp_p($_pos);

        if ($_fields['path'] == 'ENTRIES' && $_pos == 'top') {
            $obj = Request::$r->GetCurrentObject();
            //eppp_p($obj['_DOCPAR']['ENABLEOVERRIDETAX']);
            //dieFL();

            // Handle override tax checkbox
            if ($obj['_DOCPAR']['ENABLEOVERRIDETAX'] == 'true') {
                $this->SetOverrideTax($_fields['rows'], $obj);
            }
        }
        //eppp_p($_params);
        //dieFL();

        if ($_fields['path'] == 'SUBTOTALS') {

            $obj = Request::$r->GetCurrentObject();

            // The calculate link should not be shown for partially converted sales orders.
            if (!$_fields['readonly'] && $obj['SALESCONTRACT'] != 'Y') {
                $onClickCode =
                    "ReCalculateClick('$_fields[layer]','$_fields[form]','$_fields[varname]')";
                if (QXCommon::isQuixote()) { ?>
                    <div class="qx-grid-hb-action">
                        <a href="javascript:enableCalculate = false; <?= $onClickCode ?>"
                           onclick="return enableCalculate;"><?= _('Calculate'); ?></a>
                    </div>
                <? } else {
                    ?>
                    <TABLE cellpadding="0" cellspacing="0" border="0" width=100%>
                        <TR>
                            <TD valign="middle" align="right" nowrap><A
                                        href="javascript:enableCalculate = false; <?= $onClickCode ?>" class="Pick"
                                        onclick="return enableCalculate;">Calculate</A></TD>
                        </TR>
                    </TABLE>
                <? }
            } else { ?>
                <TD><FONT face="Verdana, Arial,Helvetica" size="1">&nbsp;</FONT></TD> <?
            }
        } // end of if SUBTOT
        else {
            Editor::ShowMultilineRefresh($_fields, $_pos);
        }
    }

    /**
     * @param array $_fields
     */
    //  We have to override this because there seems to be an issue with base class function where it ignores the hidden fields if numof rows is zero. Hacky fix for now.
    function ShowMultiLineFieldLayout(&$_fields)
    {
        if ($_fields['path'] == 'SUBTOTALS') {
            // JEAN :: FIX ME
            $custom_dimensions = array();
            if (!util_isPlatformDisabled()) {
                $custom_dimensions = Pt_StandardUtil::getGLDimensionFieldNames();
            }
            $_fields['hiddencolcnt'] = 15 + ($this->_deptOverride == true) + ($this->_locOverride == true);
            $_fields['actualnumofcolumns'] = 12 + ($this->_deptOverride == true) + ($this->_locOverride == true) + count($custom_dimensions);
        }
        return Editor::ShowMultiLineFieldLayout($_fields);
    }


    /**
     * @param array $_params
     * @param array $_obj
     *
     * @throws Exception
     */
    function EditorGetSuggestPrice(/** @noinspection PhpUnusedParameterInspection */ &$_params, &$_obj)
    {

        global $gManagerFactory;

        $lineno = $_obj['PRCLINENUM'];

        if (isset($lineno) && $_obj['ENTRIES'][$lineno]['ITEMID']) {

            $docparMgr = $gManagerFactory->getManager('documentparams');

            [$ID] = explode('--', $_obj['CUSTVENDID']);
            $_obj['CUSTVENDID'] = $ID;

            $docpar = $docparMgr->GetLatestRaw($_obj['DOCPARID']);
            $docpar = $docpar[0];

            $_document['PRCLISTKEY'] = $docpar['PRCLISTKEY'];
            $_document['SPCLPRCLISTKEY'] = $docpar['SPCLPRCLISTKEY'];
            $_qty = $_obj['ENTRIES'][$lineno]['UIQTY'] * $_obj['ENTRIES'][$lineno]['UNITFACTOR'];

            $pricingHandler = Globals::$g->gManagerFactory->_getObjectInstance('PricingHandler');
            $priceParams = $pricingHandler->PrepParams($_obj['CUSTVENDID'], '', '', $_obj['WHENCREATED'], $this->mod);
            $price = $pricingHandler->SuggestPrice(
                $priceParams, $_obj['ENTRIES'][$lineno]['ITEMID'],
                $_obj['ENTRIES'][$lineno]['PRODLINE'], $_qty,
                $_document
            );
            $_obj['ENTRIES'][$lineno]['UIPRICE'] = $price * $_obj['ENTRIES'][$lineno]['UNITFACTOR'];

        }
        unset($_obj['PRCLINENUM']);
    }

    /**
     * @param      array $_params
     * @param      array $obj
     * @param       bool $newDoc
     *
     * @throws Exception
     */
    function EditorGetSubTotals(&$_params, &$obj, $newDoc = true)
    {
        global $gManagerFactory;

        $this->cacheSubtotalDimensions($obj);

        /**
         * @var DocumentManager $documentMgr
         */
        $documentMgr = $gManagerFactory->getManager($_params['entity']);//, true

        /**
         * @var DocumentParamsManager $docparMgr
         */
        $docparMgr = $gManagerFactory->getManager($this->mod . 'documentparams');

        /**
         * @var DocumentParSubTotalManager $docparsubtotalsMgr
         */
        $docparsubtotalsMgr = $gManagerFactory->getManager($this->mod . 'documentparsubtotal');

        $docpar = $docparMgr->GetBaseLatest($obj['DOCPARID']);

        //eppp_p($docpar);
        $docpar['DOCPAR_SUBTOTAL'] = $docparsubtotalsMgr->getByParent($docpar['RECORDNO']);
        //eppp_p($docpar);

        $obj['_DOCPAR'] = $docpar;

        // Append dimension field information to the docvalues structure that will be used by the subtotals logic.
        $obj['PRIMARYDIMENSION'] = $documentMgr->getPrimaryDimensions();


        if ($newDoc && ($docpar['SHOW_TOTALS'] == 'true' || !empty($obj['SUBTOTALS']))) {
            $documentMgr->calcSubTotals($obj);
        }

        if ($obj['_DOCPAR']['SHOWEXPANDEDTOTALS'] != 'true') {
            $newsubtotals = array();
            $subtotals = $obj['SUBTOTALS'];
            foreach ($subtotals as $subtotal) {
                if (!$subtotal['TAXDETAIL']) {
                    $newsubtotals[] = $subtotal;
                }
            }
            $obj['SUBTOTALS'] = $newsubtotals;
        }

        $this->restoreSubtotalDimensions($obj);
        //eppp_p('----- asdfasdf -------');
        //		foreach($obj['SUBTOTALS'] as $key => $subtotal){
        //			if( isset($obj['SUBTOTALS'][$key]['ABSVAL']) && $obj['SUBTOTALS'][$key]['ABSVAL']!=0 ){
        //				$obj['SUBTOTALS'][$key]['TRX_ABSVAL'] = $obj['SUBTOTALS'][$key]['ABSVAL'];
        //			}
        //		}

    }


    /**
     * @param array $docpar
     *
     * @return array
     * @throws Exception
     */
    function CollectAutoFillData($docpar)
    {
        StartTimer("AUTOFILL");
        global $gManagerFactory;

        //$docMgr		= $gManagerFactory->GetManager('document');
        //$entryMgr	= $gManagerFactory->GetManager('documententry');

        //$inout	=	$docpar['IN_OUT'];

        // NEW
        $items = array();
        // ENDNEW

        StartTimer("ITEMS");


        $tempJSItems = array();

        $obj =& Request::$r->GetCurrentObject();

        if ($obj['ENTRIES']) {

            $itemidArray = array();

            foreach ($obj['ENTRIES'] as $entry) {
                $entry['ITEMID'] = explode('--', $entry['ITEMID']);
                $entry['ITEMID'] = $entry['ITEMID'][0];
                $itemidArray[] = $entry['ITEMID'];
            }

            $itemMgr = $gManagerFactory->getManager('item');

            $precisionFields = array('so' => 'NUMDEC_SALE', 'po' => 'NUMDEC_PUR', 'inv' => 'NUMDEC_STD');
            $precFld = $precisionFields[$this->mod];
            if ($this->state == 'shownew') {
                $itemstatus = " and icitem.status = 'T'";
            }
            $stmt = array();

            /** @noinspection PhpUndefinedVariableInspection */
            $stmt[0] = "select icitem.itemid itemid, icitem.name name,icitem.taxable tax,icitem.productlinekey prodline,
                            stduom.unit as stdunit, stduom.convfactor as convfactor, purchaseuom.unit as punit, purchaseuom.convfactor punit_factor,
                            salesuom.unit as sunit, salesuom.convfactor sunit_factor, $precFld precision, uomgrp.name as uomgrpname, icitem.itemtype itemtype,icitem.hasstartenddates, icitem.termperiod,
                            icitem.totalperiods,icitem.computeforshortterm, icitem.cost_method, icitem.enablesno, icitem.enablebin, icitem.enablelot, icitem.enableexpiration
                    from icitem, icuomgrp uomgrp, icuom stduom, icuom purchaseuom, icuom salesuom 
                    where  icitem.cny# = :1 and uomgrp.cny#(+)=icitem.cny# and uomgrp.record# (+) = icitem.uomgrpkey
                            and stduom.cny#(+)=uomgrp.cny# and purchaseuom.cny#(+)=uomgrp.cny# and salesuom.cny#(+)=uomgrp.cny# 
                            and uomgrp.record# = stduom.grpkey (+) and stduom.record# (+) = uomgrp.invdefunitkey and uomgrp.record# = purchaseuom.grpkey (+) 
                            and purchaseuom.record# (+) = uomgrp.podefunitkey and uomgrp.record# = salesuom.grpkey (+) and salesuom.record# (+) = uomgrp.sodefunitkey " . $itemstatus;


            $stmt[1] = GetMyCompany();
            $stmt = PrepINClauseStmt($stmt, $itemidArray, " and icitem.itemid ");
            //$stmt[0] .= ' order by itemid ';
            $res = QueryResult($stmt);

            $jsonVals = array();
            //Iterating to get item record details for the repeated items in the line entries
            foreach ($res as $value) {

                foreach ($value as $key => $itemValue) {
                    $jsonVals[$value['ITEMID']][strtolower($key)] = $itemValue;
                }

                $jsonVals[$value['ITEMID']]['isserialized'] = $itemMgr->IsItemSerialized($value['ITEMID'], true, $value);
            }

            $tempJSItems = str_replace('\'', '\\u0027', (Util_DataRecordFormatter::phpToJson($jsonVals)));
        }


        $items['ITEMS'] = $tempJSItems;

        StopTimer("ITEMS");

        //Queries according to the warehouse selection method
        if ($docpar['WAREHOUSESELMETHOD'] == 'Sort by Name') {
            $qry = "SELECT location_no, name FROM icwarehouse WHERE status = 'T' and cny# =:1 order by name,location_no";
            $warehouses = QueryResult(array($qry, $this->cny));
        } else {
            $qry = "SELECT location_no, name FROM icwarehouse WHERE status = 'T' and cny# =:1 order by location_no";
            $warehouses = QueryResult(array($qry, $this->cny));
        }

        $items['WHSES'] = $warehouses;

        StopTimer("AUTOFILL");
        //epp("TIMING: AUTOFILL->$af_time,ITEMS->$items_time,TOTAL->$tot_time");
        return ($items);
    }


    function PrintOnLoad()
    {

        if ($this->state != 'showview') {
            echo " DocumentOnLoad(); ";
        }
        if ($this->alertonload) {
            echo "alert('" . $this->onloadmesg . "');";
        }

        Editor::PrintOnLoad();
    }


    /**
     * @param array $_params
     */
    function SelectProcess(&$_params)
    {
        switch ($_params['state']) {
            case Editor_DeliverState:
                $docid = Request::$r->_r;
                //eppp_p($docid);
                //eppp_p($dt);
                //eppp_p($mod);

                $messagetext = Request::$r->_messagetext;
                $marketingtext = Request::$r->_marketingtext;
                //eppp_p($messagetext);
                //eppp_p($marketingtext);

                $method = Request::$r->_deliverymethod;
                //eppp_p($method);

                $values = array();
                $values['REC']['DOCID'] = $docid;
                $values['REC']['DOCPARID'] = $this->dt;
                $values['REC']['MOD'] = $this->mod;
                $values['REC']['MESSAGETEXT'] = $messagetext;
                $values['REC']['MARKETINGTEXT'] = $marketingtext;
                $values['REC']['xslformat'] = $_params['XSLFORMAT'];
                $values['REC']['xsltemplateid'] = $_params['xsltemplateid'];

                $this->Editor_Deliver($_params, $values, $method, false, $out);
                exit();
            default:
                parent::SelectProcess($_params);
        }
    }


    /**
     * @param array  $_params
     * @param array  $values
     * @param string $_method
     * @param bool   $offline
     * @param string $out
     *
     * @return bool
     * @throws Exception
     */
    function Editor_Deliver(&$_params, &$values, $_method, $offline, &$out)
    {
        //impp('DocumentEditor::Editor_Deliver');
        //impp(pp($values));
        //eppp_p($values);
        //dieFL();

        //impp($_method);
        //eppp_p($_method);
        //dieFL();

        $gErr = Globals::$g->gErr;

        $xsltemplateid = $_params['xsltemplateid'];
        $xslfname1 = $this->_params['entity'] . '_layout_print.xsl';
        $xslfname2 = $this->_params['entity'] . '_layout_edit.xsl';

        $docid = $values['REC']['DOCID'];
        $dt = $values['REC']['DOCPARID'];

        if (!$dt) {
            global $gManagerFactory;
            $docMgr = $gManagerFactory->getManager('document');
            $docpar = $docMgr->DoQuery('QRY_DOCUMENT_GET_DOCPARID', array($docid));
            $values['REC']['DOCPARID'] = $docpar[0]['DOCID'];
            $dt = $values['REC']['DOCPARID'];
        }

        $mod = $values['REC']['MOD'];
        //impp($docid);
        //impp($dt);
        //impp($mod);

        $messagetext = $values['REC']['MESSAGETEXT'];
        $marketingtext = $values['REC']['MARKETINGTEXT'];

        if (!isset($_params['ENTITYID']) || $_params['ENTITYID'] == '') {
            [$entityid] = explode('--', $values['CUSTVENDID']);
            $_params['ENTITYID'] = $entityid;
            /** @noinspection PhpUndefinedVariableInspection */
            $_params['DOCCLASS'] = ( $values['REC']['DOCCLASS'] ?: $docpar['DOCCLASS']);
        }

        $entityid = $_params['ENTITYID'];
        $docclass = $_params['DOCCLASS'];

        $iscustomdoc = false;
        if ($_method == 'xmldata' || $_method == 'xmldataraw') {
            $this->xsltemplateInfo = $this->GetTemplateType($docid, $dt, $xsltemplateid, $entityid, $docclass);
            $type = $this->xsltemplateInfo['type'];
            $iscustomdoc = ($type == 'DOC' || $type == 'DOX') ? true : false;
        }

        switch ($_method) {
            case 'xmldata' :
                $printData = $this->GetXMLForPrinting($docid, $dt, $mod, $messagetext, $marketingtext, $iscustomdoc);
                $this->PrintAsXML($printData);
                break;
            case 'xmldataraw' :
                $out = $this->GetXMLForPrinting($docid, $dt, $mod, $messagetext, $marketingtext, $iscustomdoc);
                return $out !== '';
            case 'phpdata' :
                $this->PrintAsPHP($this->GetDataForPrinting($docid, $dt, $mod));
                break;
            case 'xmlform' :
                $this->PrintAsXML(XMLUtils::PHP2XMLStr($_params));
                break;
            case 'phpform' :
                $this->PrintAsPHP($_params);
                break;
            case 'xsl' :
                $file = @file($xslfname1, 1);
                if (!$file) {
                    $file = @file($xslfname2, 1);
                }
                $xsl = join('', $file);
                $this->PrintAsXML($xsl);
                break;
            case 'fo' :
                include_once 'backend_pdf.inc';
                $xsl = $this->GetXSLTemplate($docid, $dt, $xsltemplateid, []);
                $xml = $this->GetXMLForPrinting(
                    $docid, $dt, $mod,
                    $messagetext, $marketingtext
                );
                $ok = XSLTInProcess($xsl, $xml, $fo);
                if (!$ok) {
                    $gErr->addError(
                        "BL03000021", __FILE__ . ":" . __LINE__,
                        _("XSL Translation failed")
                    );
                    return false;
                }
                $this->PrintAsXML($fo);
                break;

            /*
            case 'html' :
            */

            case 'pdf' :
            case 'pdfpreview' :
                /** @noinspection PhpUndefinedVariableInspection */
                $out = $this->generatePDFDocument($_params, $docid, $dt, $mod, $messagetext, $marketingtext, $offline, $method);
                return ($out != '');
        }
        return true;
    }


    /**
     * this function accepts a document details and depending on the docid generates the PDF for it
     * it checks if the template attached to the document is a DOC/DOCX/XSL type and does the conversion to PDF accordingly
     *
     * @param array  $_params        the parameters
     * @param string $docid          the document ID for the document to be converted
     * @param string $dt             the data for the document
     * @param string $mod            the module for the document
     * @param string $messagetext    the message text for the document
     * @param string $marketingtext  the marketing text for the document
     * @param bool   $offline        process the document offline or not
     * @param string $method         pdf or pdfpreview
     *
     * @return string
     * @throws Exception
     */
    function generatePDFDocument(&$_params, $docid, $dt, $mod, $messagetext, $marketingtext, $offline = false, $method = 'pdf')
    {
        $xsltemplateid = $_params['xsltemplateid'];
        $entityid = $_params['ENTITYID'];
        $docclass = $_params['DOCCLASS'];

        $this->xsltemplateInfo = $this->GetTemplateType($docid, $dt, $xsltemplateid, $entityid, $docclass);

        if ($this->xsltemplateInfo['type'] == 'DOC' || $this->xsltemplateInfo['type'] == 'DOX') {

            $xml = $this->GetXMLForPrinting($docid, $dt, $mod, $messagetext, $marketingtext, true);

            if (HasErrors()) {
                return false;
            }

            [$langCode, $countryCode] = explode('-', $this->xsltemplateInfo['LOCALE']);
            $langCode = ($langCode != '' ? $langCode : 'en');
            $countryCode = ($countryCode != '' ? $countryCode : 'US');

            $template = $this->xsltemplateInfo['template'];

            $params = array(
                'LANGCODE'     => $langCode,
                'COUNTRYCODE'  => $countryCode,
                'WHENMODIFIED' => $this->xsltemplateInfo['WHENMODIFIED'],
            );
            $out = genPDFFromWORD($xml, $template, !$offline, $params);

        } else {
            $fovar = $this->CreatePdfDocument($docid, $dt, $mod, $messagetext, $marketingtext);
            $out = genPDF($fovar, !$offline);
        }

        // we are using same function to do PDF and PDFPREVIEW
        // we want to mark the source document as printed only for $method='pdf'...
        if ($method == 'pdf') {
            $this->MarkDocumentAsPrinted($docid);
        }

        return $out;
    }


    /**
     * @param string $docid
     * @param string $dt
     * @param string $mod
     * @param string $messagetext
     * @param string $marketingtext
     *
     * @return bool
     */
    function CreatePdfDocument($docid, $dt, $mod, $messagetext, $marketingtext)
    {
        //impp('CreatePdfDocument');

        include_once 'backend_pdf.inc';

        $xsltemplateid = $this->_params['xsltemplateid'];
        $xsl = $this->GetXSLTemplate($docid, $dt, $xsltemplateid, []);
        $xml = $this->GetXMLForPrinting(
            $docid, $dt, $mod,
            $messagetext, $marketingtext
        );

        if (!XSLTInProcess($xsl, $xml, $fo)) {
            $gErr = Globals::$g->gErr;
            $gErr->addError(
                "BL03000021", __FILE__ . ":" . __LINE__,
                _("XSL Translation failed")
            );
            return false;
        }

        return $fo;
    }


    /**
     * @param string $docid
     *
     * @return bool|string[][]
     * @throws Exception
     */
    function MarkDocumentAsPrinted($docid)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;

        $docMgr = $gManagerFactory->getManager('document');

        $ok = $docMgr->_QM->beginTrx('MarkDocumentAsPrinted');
        $ok = $ok && $docMgr->DoQuery('QRY_DOCUMENT_MARK_AS_PRINTED', array($docid));
        $ok = $ok && $docMgr->_QM->commitTrx('MarkDocumentAsPrinted');

        if (!$ok) {
            $docMgr->_QM->rollbackTrx('MarkDocumentAsPrinted');
        }

        return $ok;
    }


    /**
     * @param string            $docid
     * @param array|bool|string $docparid
     * @param string            $xsltemplateid
     * @param string            $entityid
     * @param string            $docclass
     *
     * @return mixed
     * @throws Exception
     */
    public function GetTemplateType($docid, $docparid, $xsltemplateid = '', $entityid = '', $docclass = '')
    {
        $indexKey = $docparid . '#~#' . $xsltemplateid . '#~#' . $entityid . '#~#' . $docclass;

        if (!isset($this->printTemplateCache[$indexKey])) {
            $gManagerFactory = Globals::$g->gManagerFactory;
            $XslformatMgr = $gManagerFactory->getManager('xslformat');

            //Check the Docpar for the default template to use
            if (!isset($xsltemplateid) || $xsltemplateid == '') {

                if (!$docparid) {
                    $docMgr = $gManagerFactory->getManager('document');
                    $docparid = $docMgr->DoQuery('QRY_DOCUMENT_GET_DOCPARID', array($docid));
                    $docparid = $docparid[0]['DOCID'];
                }

                $docparMgr = $gManagerFactory->getManager('documentparams');
                $docpar = $docparMgr->GetBaseLatest($docparid);

                $xsltemplateid = $docpar['XSLTEMPLATE'];
            } else {
                $args = array(
                    'selects' => array('RECORDNO'),
                    'filters' => array(array(array('DESCRIPTION', '=', $xsltemplateid)))
                );
                $resultSet = $XslformatMgr->GetList($args);
                $xsltemplateid = $resultSet[0]['RECORDNO'];
            }

            if ($xsltemplateid) {
                $this->XSL_Template_Type = 'db'; // remember what type of transform process we are using

                $formatdata = $XslformatMgr->DoQuery('QRY_XSLFORMAT_SELECT_RAW_FROM_RECORDNO', array($xsltemplateid));
                if (isset($formatdata[0]['XSL'])) {
                    $formatdata[0]['XSL'] = databaseStringUncompress($formatdata[0]['XSL']);
                }
                $formatdata = $formatdata[0];

                // transform db value into business value for easy processing of preferences
                DocformatEditor::buildBizView($formatdata);
                $formatdata['type'] = $formatdata['TEMPLATETYPE'];
                $formatdata['template'] = $formatdata['XSL'];

                //$result = array('type' => $formatdata['TEMPLATETYPE'], 'template' => $formatdata['XSL']);
                $result = $formatdata;
            }

            /** @noinspection PhpUndefinedVariableInspection */
            $this->printTemplateCache[$indexKey] = ($result ?: array( 'type' => NULL, 'template' => NULL));
        }

        return $this->printTemplateCache[$indexKey];
    }

    /**
     * @param  string            $docid
     * @param  array|bool|string $docparid
     * @param string             $xsltemplateid
     * @param array              $unusedParams   for signature compatibility with DocumentFormEditor
     *
     * @return string
     */
    function GetXSLTemplate($docid, $docparid, $xsltemplateid, /** @noinspection PhpUnusedParameterInspection */ $unusedParams)
    {
        //eppp_p('GetXSLTemplate');
        //eppp_p($docparid);

        $gManagerFactory = Globals::$g->gManagerFactory;

        $XslformatMgr = $gManagerFactory->getManager('xslformat');

        if (!isset($xsltemplateid) || $xsltemplateid == '') {
            if (!$docparid) {
                $docMgr = $gManagerFactory->getManager('document');
                $docparid = $docMgr->DoQuery('QRY_DOCUMENT_GET_DOCPARID', array($docid));
                $docparid = $docparid[0]['DOCID'];
            }
            //eppp_p($docparid);
            //dieFL();

            //Check the Docpar for the default template to use
            $docparMgr = $gManagerFactory->getManager('documentparams');
            $docpar = $docparMgr->GetBaseLatest($docparid);
            //eppp_p($docpar);
            //dieFL();

            $xsltemplateid = $docpar['XSLTEMPLATE'];
        } else {
            $args = array(
                'selects' => array('RECORDNO'),
                'filters' => array(array(array('DESCRIPTION', '=', $xsltemplateid)))
            );
            $resultSet = $XslformatMgr->GetList($args);
            $xsltemplateid = $resultSet[0]['RECORDNO'];
        }

        if ($xsltemplateid != '') {
            $this->XSL_Template_Type = 'db'; // remember what type of transform process we are using

            $formatdata = $XslformatMgr->DoQuery('QRY_XSLFORMAT_SELECT_RAW_FROM_RECORDNO', array($xsltemplateid));

            $file = ($formatdata[0]['XSL']) ? $XslformatMgr->GetXSL(databaseStringUncompress($formatdata[0]['XSL'])) : '';
        }
        //dieFL($file);

        // Go for the old method
        /** @noinspection PhpUndefinedVariableInspection */
        if (!$file) {
            if ($this->mod == 'inv') {
                /** @noinspection PhpUndefinedVariableInspection */
                $fileName = $docpar['SALE_PUR_TRANS'] . '_Inventory';
            } else {
                /** @noinspection PhpUndefinedVariableInspection */
                $fileName = $docpar['SALE_PUR_TRANS'] . '_' . $docpar['DOCCLASS'];
            }
            $file = @file(XSLDIR . $fileName . '_layout_print.xsl', 1);
            $this->XSL_Template_Type = 'file_print_layout';
            if (!$file) {
                $this->XSL_Template_Type = 'entity_print_layout';
                $file = @file(XSLDIR . $this->_params['entity'] . '_layout_print.xsl', 1);
                if (!$file) {
                    $this->XSL_Template_Type = 'entity_edit_layout';
                    $file = @file(XSLDIR . $this->_params['entity'] . '_layout_edit.xsl', 1);
                }
            }
            $file = join('', $file);
        }

        //dieFL(XSLDIR.$fileName.'_layout_print.xsl');
        return ($file);
    }


    /**
     * @param array $_params
     */
    function MergeOwnerDimensionFields(&$_params)
    {
        $pagenumber = 1;
        $this->calcOwnerDimensionFields($_params, $pagenumber);
    }


    /**
     * @param null|int|string $docid
     * @param string          $dt
     * @param string          $mod
     * @param bool            $iscustomdoc
     *
     * @return array
     * @throws Exception
     */
    function GetDataForPrinting($docid = 0, $dt = '', $mod = '', $iscustomdoc = false)
    {
        //eppp_p('GetDataForPrinting');
        //eppp_p($docid);
        //dieFL();

        $gManagerFactory = Globals::$g->gManagerFactory;
        $gErr = Globals::$g->gErr;

        /**
         * @var DocumentManager $entityMgr
         */
        $entityMgr = $gManagerFactory->getManager($this->_params['entity'], true, array( 'DOCTYPE' => $dt));

        if (!$docid) {
            $vid = $entityMgr->GetKeyFieldName();
            $docid = Request::$r->{Request::$r->PathToFieldName($vid)};
        }

        if ($iscustomdoc && $this->xsltemplateInfo['PARAMS'] != '') {
            // for custom document association we get document data through different API
            $document = $entityMgr->getPrintableInfo($docid, $this->xsltemplateInfo);

            // fetch custom relationship attributes...
            $this->fetchRelationshipValues($entityMgr, $document);

        } else {
            // lets just use manager->Get($docid) method to get document data...
            $document = $entityMgr->Get($docid);

            // lets process the document and gather project related information, only for sodocument
            $entityMgr->getProjectInvoiceInfo($document);
        }

        //LogToFile(pp($document)."\n");

        if (!$document) {
            $gErr->addError("BL03000021", __FILE__ . ":" . __LINE__, "ERROR: couldnt fetch the given docid ($docid) information...");
            return array();
        }

        $this->ExpandKitForPrinting($document);

        if ($iscustomdoc) {
            // the logic of showing or hiding subtotal details is controlled in below API
            // following line is commented for bug#: 39344
            //$this->EditorGetSubTotals($this->_params, $document, false);
            if (!isset($document['_DOCPAR']['SHOWEXPANDEDTOTALS']) || $document['_DOCPAR']['SHOWEXPANDEDTOTALS'] == 'false') {
                $newsubtotals = array();
                $subtotals = $document['SUBTOTALS'];
                foreach ($subtotals as $subtotal) {
                    if (!$subtotal['TAXDETAIL']) {
                        $newsubtotals[] = $subtotal;
                    }
                }
                $document['SUBTOTALS'] = $newsubtotals;
            }

            // remove field which type is "PASSWORD" in $document.
            foreach ($entityMgr->customFields as $cField) {
                $key = $cField->customFieldID;
                $type = $cField->type;
                if (!is_null($key) && $type == "PASSWORD") {
                    unset($document[$key]);
                }
                // reformat the field which type is "DATE" for display
                if (!is_null($key) && $type == "DATE") {
                    $document[$key] = FormatDateForDisplay($document[$key]);
                }
            }

            $documententryMgr = $this->getEntryManager();
            for ($i = 0; $i < count($document['ENTRIES']); $i++) {
                foreach ($documententryMgr->customFields as $cField) {
                    $key = $cField->customFieldID;
                    $type = $cField->type;
                    // remove field which type is "PASSWORD" in $document['ENTRIES'].
                    if (!is_null($key) && $type == "PASSWORD") {
                        unset($document['ENTRIES'][$i][$key]);
                    }
                    // reformat the field which type is "DATE" for display
                    if (!is_null($key) && $type == "DATE") {
                        $document['ENTRIES'][$i][$key] = FormatDateForDisplay($document['ENTRIES'][$i][$key]);
                    }
                }
            }
        }

        //Split up the itemid and name
        $hasItemsWithMoreLength = false;
        foreach ($document['ENTRIES'] as $key => $entry) {
            [$item] = explode('--', $entry['ITEMID']);
            $document['ENTRIES'][$key]['ITEMID'] = $item;
            if (isl_strlen($entry['ITEMID']) > 21) {
                $hasItemsWithMoreLength = true;
            }
        }

        // getting the totaldue value for custom invoice
        $totaldue = 0;
        if (isset($document['PRRECORDKEY']) && $document['PRRECORDKEY'] != '') {
            $prrecordMgr = $gManagerFactory->getManager('prrecord');
            $rec = $prrecordMgr->GetList(
                array(
                    'selects'        => array('TOTALDUE'),
                    'filters'        => array(array(array('RECORDNO', '=', $document['PRRECORDKEY']))),
                    'donottransform' => true
                )
            );
            if ($rec) {
                $totaldue = $rec[0]['TOTALDUE'];
            }
        }
        $document['PRRECORD']['TOTALDUE'] = Currency($totaldue);

        /** @var DocumentParamsManager $docparMgr */
        $docparMgr = $gManagerFactory->getManager('documentparams');
        $document['_DOCPAR'] = $docparMgr->Get($document['DOCPARKEY']);

        if ($this->_ismcpEnabled) {
            $document['MULTICURRENCY'] = 'true';
            $trxCurrencyMgr = $gManagerFactory->getManager('trxcurrencies');
            $CurrencyInfo = $trxCurrencyMgr->GetCurrencyInfo($document['CURRENCY']);
            if ($CurrencyInfo['SYMBOL'] == '�') {
                $CurrencyInfo['SYMBOL'] = '&#8364;';
                $document['TRX_CURRENCY_SYMBOL'] = $CurrencyInfo['SYMBOL'];
            } else {
                $document['TRX_CURRENCY_SYMBOL'] = $CurrencyInfo['SYMBOL'];
            }
            $basecurrency = GetBaseCurrency();
            $transactioncurrency = $document['CURRENCY'];

            if ($basecurrency != $transactioncurrency) {
                $this->ProcessMultiCurrencyLineEntriesForBlob($document, $iscustomdoc);
            }
        } else {
            $trxCurrencyMgr = $gManagerFactory->getManager('trxcurrencies');
            $CurrencyInfo = $trxCurrencyMgr->GetCurrencyInfo(GetBaseCurrency());
            if (!isset($CurrencyInfo['SYMBOL'])) {
                $CurrencyInfo['SYMBOL'] = "$";
            }
            if ($CurrencyInfo['SYMBOL'] == '�') {
                $CurrencyInfo['SYMBOL'] = '&#8364;';
                $document['TRX_CURRENCY_SYMBOL'] = $CurrencyInfo['SYMBOL'];
            } else {
                $document['TRX_CURRENCY_SYMBOL'] = $CurrencyInfo['SYMBOL'];
            }
            //$document['TRX_CURRENCY_SYMBOL'] = $CurrencyInfo['SYMBOL']= "$";
        }

        // this is for bug#19977
        if ($hasItemsWithMoreLength) {
            foreach ($document['ENTRIES'] as $key => $entry) {
                $isWhiteSpaceExists = isl_preg_match("' '", $entry['ITEMID']);
                if (!$isWhiteSpaceExists && isl_strlen($entry['ITEMID']) > 21) {
                    $newitemid = isl_substr($entry['ITEMID'], 0, 20) . " " . isl_substr($entry['ITEMID'], 20);
                    $document['ENTRIES'][$key]['ITEMID'] = $newitemid;
                }
            }
        }

        if ($iscustomdoc) {
            // for intacct toolbar's fields
            global $kSOid, $kPOid, $kINVid;
            $modArray = array('so' => $kSOid, 'po' => $kPOid, 'inv' => $kINVid);
            $precisionFields = array('so' => 'NUMDEC_SALE', 'po' => 'NUMDEC_PUR', 'inv' => 'NUMDEC_STD');
            GetModulePreferences($modArray[$this->mod], $prefs);
            $appPrecision = ($prefs['ITEMPRECISION']) ?: 2;

            foreach ($document['ENTRIES'] as $key => $entry) {
                if ($entry['ITEM'][$precisionFields[$this->mod]] != '') {
                    $itemPrecision = $entry['ITEM'][$precisionFields[$this->mod]];
                } else {
                    $itemPrecision = $appPrecision;
                }

                $document['ENTRIES'][$key]['PRICE'] = ibcmul($document['ENTRIES'][$key]['PRICE'], '1', $itemPrecision, false);

                // format total fields
                if (array_key_exists('GROUPTOTAL_PRICE', $document['ENTRIES'][$key])) {
                    $document['ENTRIES'][$key]['GROUPTOTAL_PRICE'] = ibcmul($document['ENTRIES'][$key]['GROUPTOTAL_PRICE'], '1', $itemPrecision, false);
                }

                $document['ENTRIES'][$key]['LINE_NO'] = $document['ENTRIES'][$key]['LINE_NO'] + 1;
                $document['ENTRIES'][$key]['EXCHRATETYPE'] = $document['EXCHRATETYPES']['NAME'];
                $document['ENTRIES'][$key]['TRX_CURRENCY_SYMBOL'] = $document['TRX_CURRENCY_SYMBOL'];
                $document['ENTRIES'][$key]['ITEM']['TAXABLE'] = ($document['ENTRIES'][$key]['ITEM']['TAXABLE'] == 'true') ? 'T' : '';

                $document['ENTRIES'][$key]['EXCHRATE'] = ibcmul($document['ENTRIES'][$key]['EXCHRATE'], '1', 8, true) . '';
                $document['ENTRIES'][$key]['EXCHRATE'] = is_int($document['ENTRIES'][$key]['EXCHRATE'] + 0) ? ibcmul($document['ENTRIES'][$key]['EXCHRATE'], '1', 2, false) : $document['ENTRIES'][$key]['EXCHRATE'];
                $document['ENTRIES'][$key]['TOTAL'] = ibcmul($document['ENTRIES'][$key]['TOTAL'], '1', 2, true);
                $document['ENTRIES'][$key]['TOTAL'] = ibcmul($document['ENTRIES'][$key]['TOTAL'], '1', 2, false);

                // format total fields
                if (array_key_exists('GROUPTOTAL_VALUE', $document['ENTRIES'][$key])) {
                    $document['ENTRIES'][$key]['GROUPTOTAL_VALUE'] = ibcmul($document['ENTRIES'][$key]['GROUPTOTAL_VALUE'], '1', 2, false);
                }

                // reformat the dates for display
                $document['ENTRIES'][$key]['WHENCREATED'] = FormatDateForDisplay($document['ENTRIES'][$key]['WHENCREATED']);
                $document['ENTRIES'][$key]['WHENPOSTED'] = FormatDateForDisplay($document['ENTRIES'][$key]['WHENPOSTED']);
                $document['ENTRIES'][$key]['WHENDUE'] = FormatDateForDisplay($document['ENTRIES'][$key]['WHENDUE']);
                $document['ENTRIES'][$key]['WHENPAID'] = FormatDateForDisplay($document['ENTRIES'][$key]['WHENPAID']);
                $document['ENTRIES'][$key]['WHENMODIFIED'] = FormatDateForDisplay($document['ENTRIES'][$key]['WHENMODIFIED']);
                $document['ENTRIES'][$key]['WHENDISCOUNT'] = FormatDateForDisplay($document['ENTRIES'][$key]['WHENDISCOUNT']);
                $document['ENTRIES'][$key]['EXCHRATEDATE'] = FormatDateForDisplay($document['ENTRIES'][$key]['EXCHRATEDATE']);
                $document['ENTRIES'][$key]['REVRECSTARTDATE'] = FormatDateForDisplay($document['ENTRIES'][$key]['REVRECSTARTDATE']);
                $document['ENTRIES'][$key]['REVRECENDDATE'] = FormatDateForDisplay($document['ENTRIES'][$key]['REVRECENDDATE']);
                $document['ENTRIES'][$key]['SC_REVRECSTARTDATE'] = FormatDateForDisplay($document['ENTRIES'][$key]['SC_REVRECSTARTDATE']);
                $document['ENTRIES'][$key]['SC_REVRECENDDATE'] = FormatDateForDisplay($document['ENTRIES'][$key]['SC_REVRECENDDATE']);
                $document['ENTRIES'][$key]['SC_STARTDATE'] = FormatDateForDisplay($document['ENTRIES'][$key]['SC_STARTDATE']);
            }

            foreach ( $document['SUBTOTALS'] as $key => $entry) {
                $document['SUBTOTALS'][$key]['TRX_CURRENCY_SYMBOL'] = $document['TRX_CURRENCY_SYMBOL'];
                $abstotal = ($document['SUBTOTALS'][$key]['ABSVAL']) ?:
                    $document['SUBTOTALS'][$key]['TOTAL'];
                $trxabstotal = ($document['SUBTOTALS'][$key]['TRX_ABSVAL']) ?:
                    $document['SUBTOTALS'][$key]['TRX_TOTAL'];

                $mytotal = ($document['SUBTOTALS'][$key]['TOTAL']) ?: $document['SUBTOTALS'][$key]['ABSVAL'];
                $document['SUBTOTALS'][$key]['TOTAL'] = ibcmul($mytotal, '1', 2, true);
                $document['SUBTOTALS'][$key]['TOTAL'] = ibcmul($document['SUBTOTALS'][$key]['TOTAL'], '1', 2, false);

                $document['SUBTOTALS'][$key]['TRX_TOTAL'] = ibcmul($trxabstotal, '1', 2, true);
                $document['SUBTOTALS'][$key]['TRX_TOTAL'] = ibcmul($document['SUBTOTALS'][$key]['TRX_TOTAL'], '1', 2, false);
            }

            /** @noinspection PhpUndefinedVariableInspection */
            $document['TOTAL'] = $abstotal;
            $document['TOTAL'] = ibcmul($document['TOTAL'], '1', 2, true);
            $document['TOTAL'] = ibcmul($document['TOTAL'], '1', 2, false);
            $document['SUBTOTAL'] = ibcmul($document['SUBTOTAL'], '1', 2, true);
            $document['SUBTOTAL'] = ibcmul($document['SUBTOTAL'], '1', 2, false);
            /** @noinspection PhpUndefinedVariableInspection */
            $document['TRX_TOTAL'] = $document['SUBTOTALS'][$key]['TRX_TOTAL'];
            $document['TOTAL_DUE'] = Currency($totaldue);
            // reformat these fields, like from 5.00000000 to 5.00, 0.73200000 to 0.732
            $document['EXCHRATE'] = ibcmul($document['EXCHRATE'], '1', 8, true) . '';
            $document['EXCHRATE'] = is_int($document['EXCHRATE'] + 0) ? ibcmul($document['EXCHRATE'], '1', 2, false) : $document['EXCHRATE'];

            // reformat the dates for display
            $document['WHENCREATED'] = FormatDateForDisplay($document['WHENCREATED']);
            $document['WHENPOSTED'] = FormatDateForDisplay($document['WHENPOSTED']);
            $document['WHENDUE'] = FormatDateForDisplay($document['WHENDUE']);
            $document['WHENPAID'] = FormatDateForDisplay($document['WHENPAID']);
            $document['WHENMODIFIED'] = FormatDateForDisplay($document['WHENMODIFIED']);
            $document['WHENDISCOUNT'] = FormatDateForDisplay($document['WHENDISCOUNT']);
            $document['EXCHRATEDATE'] = FormatDateForDisplay($document['EXCHRATEDATE']);
        }

        global $kAVAid;
        $avalaraEnabled = GetPreferenceForProperty($kAVAid, 'AVA_ENABLE_SO');
        $ava_disp_detail_taxlines = GetPreferenceForProperty($kAVAid, 'AVA_DISP_DETAIL_TAXLINES');
        if ($avalaraEnabled == 'T' && $ava_disp_detail_taxlines != 'T') {
            $avaSubtotals = array();
            foreach ( $document['SUBTOTALS'] as $val) {
                if (isl_substr($val['TAXDETAIL3P'], 0, 6) != 'AVATAX') {
                    $avaSubtotals[] = $val;
                }
            }
            $document['SUBTOTALS'] = $avaSubtotals;
        }
        if ($document['STATE'] == 'Draft') {
            // Append "DRAFT" to prevent fraud when printing draft document
            if (isset($document['DOCID'])) {
                $document['DOCID'] .= '-DRAFT';
            }
            if (isset($document['DOCNO'])) {
                $document['DOCNO'] .= '-DRAFT';
            }
        }

        $printData = array(
            'COMPANY'        => $this->GetCompanyData(true, $iscustomdoc),
            'LOCATIONENTITY' => $this->GetLocationEntityData($document['MELOCATIONKEY']),
            'REC'            => $document
        );

        // the following credit cardinfo & remitto address are added for
        // custom invoice xls for a client.
        $company = GetCompanyDataForXML();
        $printData['COMPANY']['CreditCardsAccepted'] = $company['CreditCardsAccepted'];
        $printData['COMPANY']['CreditCards'] = $company['CreditCards'];
        $printData['COMPANY']['RemitToAddr'] = $company['RemitToAddr'];

        $billaddr1 = $printData['REC']['BILLTO']['MAILADDRESS']['ADDRESS1'];
        $billaddr2 = $printData['REC']['BILLTO']['MAILADDRESS']['ADDRESS2'];

        $shipaddr1 = $printData['REC']['SHIPTO']['MAILADDRESS']['ADDRESS1'];
        $shipaddr2 = $printData['REC']['SHIPTO']['MAILADDRESS']['ADDRESS2'];

        $printData['REC']['BILLTO']['MAILADDRESS']['ADDRESS1'] = MailaddressManager::GetTrimAddress($billaddr1);
        $printData['REC']['BILLTO']['MAILADDRESS']['ADDRESS2'] = MailaddressManager::GetTrimAddress($billaddr2);

        $printData['REC']['SHIPTO']['MAILADDRESS']['ADDRESS1'] = MailaddressManager::GetTrimAddress($shipaddr1);
        $printData['REC']['SHIPTO']['MAILADDRESS']['ADDRESS2'] = MailaddressManager::GetTrimAddress($shipaddr2);

        $isVendor = false;

        if ($this->mod == 'so') {
            $entMgr = $gManagerFactory->getManager('customer');
        } else {
            $entMgr = $gManagerFactory->getManager('vendor');
            $isVendor = true;
        }

        $custvendEntity = $entMgr->GetRaw($printData['REC']['CUSTVENDID']);
        $printData['REC']['CUSTVENDNAME'] = $custvendEntity[0]['NAME'];
        $printData['REC']['CUSTVEND_TAXID'] = $custvendEntity[0]['TAXID'];

        if ( $isVendor ) {
            $entityMgr->decryptFields($printData['REC']);
        }

        return $printData;
    }


    /**
     * @return EntityManager
     */
    protected function getEntryManager()
    {
        return $this->GetManager($this->_params['entity'] . 'entry');
    }


    /**
     * This function fetches all the values for platform relationship fields
     * ideally emgr->getList() should provide these but in absense this functions tries to retrieve
     * this function is heavily inspired from FormEditor->fetchPlatformRels()
     * if we atleast have one custom dimension created...
     *
     * @param EntityManager $entityMgr object entity manager instance
     * @param array         $document  array  array of current document values
     */
    protected function fetchRelationshipValues($entityMgr, &$document)
    {
        // fetch custom relationship attributes...
        if (!util_isPlatformDisabled()) {
            $docEntryObjects = array('invdocumententry', 'podocumententry', 'sodocumententry', 'documententry');
            $ownedObjects =& $entityMgr->GetOwnedObjects();

            foreach ($ownedObjects as $objRec) {
                // we want to loop only for docentry entities...
                if (!in_array($objRec['entity'], $docEntryObjects)) {
                    continue;
                }

                $mgr = $this->GetManager($objRec['entity']);
                $customEntity = $mgr->GetCustomComponentsEntity();
                $platformDef = Pt_StandardUtil::getObjDef($customEntity);

                // skip loop if no relationship found...
                if (!$platformDef) {
                    continue;
                }

                $platformRels = Pt_StandardUtil::getRelationshipFields($platformDef);

                foreach ($document[$objRec['path']] as $idx => $row) {
                    foreach ($platformRels as $field) {
                        $fieldName = isl_strtoupper($field->getFieldName());
                        /**
                         * @var Pt_FieldRelationship $uiField
                         */
                        $uiField = $field->getUIField();

                        $value = Pt_RelationshipManagerChoose::getObjectIds(
                            $field->getRelationshipDef(),
                            $field->getObjectDefId(),
                            $row['RECORDNO']
                        );

                        $ids = NULL;
                        if ($value instanceof Pt_ArrayIds) {
                            $ids = $value->getIds();
                        }

                        if (isset($ids[0])) {
                            $getObjectDef2 = $uiField->getObjectDef2();

                            $lookup2FieldName = '';
                            $lookupTemplateFields = $getObjectDef2->getLookupTemplateFields();
                            if ($lookupTemplateFields[1]) {
                                $lookup2FieldName = $lookupTemplateFields[1]->getFieldName();
                            }

                            $data = Pt_DataObjectManager::getById($getObjectDef2, $ids[0]);
                            $allData = $data->getFullFieldMap();

                            $document[$objRec['path']][$idx][$fieldName] = $allData['name'];
                            if ($allData[$lookup2FieldName] != '') {
                                $document[$objRec['path']][$idx][$fieldName] .= '--' . $allData[$lookup2FieldName];
                            }
                        }
                    }
                }
            }
        }

    }

    /**
     * @param string $docid
     * @param string $dt
     * @param string $mod
     * @param string $messagetext
     * @param string $marketingtext
     * @param bool   $iscustomdoc
     *
     * @return string
     * @throws Exception
     */
    function GetXMLForPrinting($docid, $dt, $mod, $messagetext, $marketingtext, $iscustomdoc = false)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;

        $entityMgr = $this->GetManager($this->_params['entity']);

        // build XML for MailMerge Web Service
        if ($iscustomdoc) {

            $sodata = $this->GetDataForPrinting($docid, $dt, $mod, true);
            $xml = XMLUtils::BuildWSXML($sodata);

        } else {

            $useBlob = true;

            // decide if we can use the generated blob to the document
            // for mega companies with not owned document or restricted users we will have to regenerate the xml
            if (IsMultiEntityCompany()) {
                $useBlob = ($entityMgr->IsOwned($docid) && !IsRestrictedUser() ? true : false);
            }

            if ($useBlob) {
                $blobStoreMgr = $gManagerFactory->getManager('blobstore');
                $xml = $blobStoreMgr->GetByParent($docid, 'INVDOCXML');
                assert(is_string($xml));

                //Format date for printing
                $this->ProcessDateFormatForPrinting($xml, $docid);
            }

            // if we still dont have the xml then lets query and get it...
            /** @noinspection PhpUndefinedVariableInspection */
            if (!$xml) {
                $dataForPrinting = $this->GetDataForPrinting($docid, $dt, $mod);
                $xml = XMLUtils::PHP2StdXMLStr($dataForPrinting);
            }
        }

        // add message text, marketing text
        $this->GetMessageAndMarketingTextForPrinting($xml, $messagetext, $marketingtext, $iscustomdoc);

        // For ME shared and entity context, append entity details
        $this->GetEntityDetailsForPrinting($xml, $iscustomdoc);

        // process document XML root
        $this->ProcessXMLRoot($xml, $iscustomdoc);

        return $xml;
    }


    /**
     *        Expanding the kit line entry to multiple lines for printing
     *
     * @param  array $document
     *
     * @throws Exception
     */
    function ExpandKitForPrinting(&$document)
    {
        global $gManagerFactory;

        $docEntryDetailMgr = $gManagerFactory->getManager('docentrydetail');

        $expandedEntries = array();

        foreach ($document['ENTRIES'] as $key => $entry) {
            if ($entry['ITEM']['ITEMTYPE'] == 'Kit' && $entry['ITEM']['REVPRINTING'] == 'Individual Components') {
                $docID = $document['DOCID'];
                $lineNo = $key;

                $kitItemInfos = $docEntryDetailMgr->DoQuery(
                    'QRY_DOCENTRYDETAIL_GETKITDETAIL_BY_DOCID_LINENO',
                    array($this->cny, $docID, $lineNo)
                );

                if (sizeof($kitItemInfos) > 0) {
                    foreach ($kitItemInfos as $kitItemInfo) {
                        $newKitItemEntry = $entry;
                        $newKitItemEntry['ITEMID'] = $kitItemInfo['ITEMID'];
                        $newKitItemEntry['ITEMDESC'] = $kitItemInfo['ITEMDESC'];
                        $newKitItemEntry['UNIT'] = $kitItemInfo['ITEMUNIT']; //using the kit component unit
                        $newKitItemEntry['QUANTITY'] = $kitItemInfo['ITEMQUANTITY'] * $newKitItemEntry['QUANTITY']; //the real kit component quantity
                        $newKitItemEntry['PRICE'] = $kitItemInfo['INVOICEPRICE'];
                        $newKitItemEntry['TOTAL'] = $kitItemInfo['INVOICEPRICE'];
                        $newKitItemEntry['UIPRICE'] = $kitItemInfo['INVOICEPRICE'];   //this is displayed in pdf
                        $newKitItemEntry['UIVALUE'] = $kitItemInfo['INVOICEPRICE'];   //this is displayed in pdf

                        $expandedEntries[] = $newKitItemEntry;
                    }
                } else {
                    $expandedEntries[] = $entry;
                }
            } else {
                $expandedEntries[] = $entry;
            }
        }

        $document['ENTRIES'] = $expandedEntries;
    }

    /**
     * @param string      $xml
     * @param null|string $docid
     *
     * @return mixed|string
     */
    function ProcessDateFormatForPrinting(&$xml, $docid)
    {
        $entityMgr = $this->GetManager($this->_params['entity']);

        if (!$docid) {
            $vid = $entityMgr->GetKeyFieldName();
            $docid = Request::$r->{Request::$r->PathToFieldName($vid)};
        }

        $document = $entityMgr->get($docid);

        $dateFlds = array();
        foreach ($entityMgr->_fieldInfoMap as $fld) {
            if ($fld['type']['type'] == 'date') {
                $dateFlds[] = $fld['path'];
            }
        }

        foreach ($dateFlds as $dfld) {
            if ($document[$dfld] != '') {
                $_wstart = isl_strpos($xml, '<' . $dfld);
                $start = $_wstart + strlen($dfld) + 2;
                $end = isl_strpos($xml, '</' . $dfld);
                if ($start != '' && $end != '') {
                    $xml = isl_substr($xml, 0, $start) . FormatDateForDisplay($document[$dfld]) . isl_substr($xml, $end);
                }
            }
        }

        // This is nothing to do with DateFormat. We are adding -DRAFT in DOCID and DOCNO when printing draft documents
        if (isset($document['STATE']) && $document['STATE'] == 'Draft') {
            $xml = str_replace('<DOCID>' . $docid . '</DOCID>', '<DOCID>' . $docid . '-DRAFT</DOCID>', $xml);
            if (isset($document['DOCNO']) && $document['DOCNO'] != '') {
                $docno = $document['DOCNO'];
                $xml = str_replace('<DOCNO>' . $docno . '</DOCNO>', '<DOCNO>' . $docno . '-DRAFT</DOCNO>', $xml);
            }
        }
        return $xml;

    }

    /**
     * extracts and removes marketing text from the input xml
     *
     * @param string $xml
     * @param string $messagetext
     * @param string $marketingtext
     * @param bool   $iscustomdoc
     *
     * @return string
     */
    function GetMessageAndMarketingTextForPrinting(&$xml, $messagetext, $marketingtext, $iscustomdoc)
    {
        $hasmsgtxt = isset($messagetext) && $messagetext !== '';
        $hasmkttxt = isset($marketingtext) && $marketingtext !== '';
        //If Marketing text not set then take from company, it has been used in Quench Custom Invoices
        if (!$hasmsgtxt || !$hasmkttxt) {
            $companyData = $this->GetCompanyData(true, $iscustomdoc);
            if (!$hasmsgtxt) {
                $messagetext = $companyData['MESSAGE_TEXT'];
            }
            if (!$hasmkttxt) {
                $marketingtext = $companyData['MARKETING_TEXT'];
            }
        }
        //Remove special characters
        $messagetext = XMLUtils::xmlSpecialChars($messagetext);
        $marketingtext = XMLUtils::xmlSpecialChars($marketingtext);

        // stick message text & marketing text within XML
        if ($iscustomdoc) {
            $_cmtstart = isl_strpos($xml, "<key>COMPANY_MESSAGE_TEXT</key>\n<value>");
            if ($_cmtstart != false) {
                $start = $_cmtstart + 39;
                $end = isl_strpos($xml, '</value>', $start);
                $xml = isl_substr($xml, 0, $start) . $messagetext . isl_substr($xml, $end);
            }
            $_cmtstart = isl_strpos($xml, "<key>COMPANY_MARKETING_TEXT</key>\n<value>");
            if ($_cmtstart != false) {
                $start = $_cmtstart + 41;
                $end = isl_strpos($xml, '</value>', $start);
                $xml = isl_substr($xml, 0, $start) . $marketingtext . isl_substr($xml, $end);
            }
        } else {
            $_mtstart = isl_strpos($xml, '<MESSAGE_TEXT>');
            if ($_mtstart != false) {
                $start = $_mtstart + 14;
                $end = isl_strpos($xml, '</MESSAGE_TEXT>');
                $xml = isl_substr($xml, 0, $start) . $messagetext . isl_substr($xml, $end);
            }
            $_mtstart = isl_strpos($xml, '<MARKETING_TEXT>');
            if ($_mtstart != false) {
                $start = $_mtstart + 16;
                $end = isl_strpos($xml, '</MARKETING_TEXT>');
                $xml = isl_substr($xml, 0, $start) . $marketingtext . isl_substr($xml, $end);
            }
        }

        return $xml;
    }


    /**
     * Adds <ENTITY_INFO> XML struct into XML for printing for ME Shared and at entity context.
     *
     * Constructs structure as below and appends to XML after </COMPANY> tag,
     *   <ENTITY_INFO>
     *        <NAME></NAME>
     *        <ID></ID>
     *        <REPORTPRINTAS></REPORTPRINTAS>
     *        <WEEKSTART></WEEKSTART>
     *        <START_DATE></START_DATE>
     *        <ADDR1></ADDR1>
     *        <ADDR2></ADDR2>
     *        <CITY></CITY>
     *        <STATE></STATE>
     *        <ZIP></ZIP>
     *        <COUNTRY></COUNTRY>
     *        <PRINTAS></PRINTAS>
     *        <PHONE1></PHONE1>
     *        <EMAIL1></EMAIL1>
     *    </ENTITY_INFO>
     *
     * @param string $xml         input XML
     * @param bool   $iscustomdoc if custom document
     *
     * @return string   output XML
     */
    function GetEntityDetailsForPrinting(&$xml, /** @noinspection PhpUnusedParameterInspection */ $iscustomdoc)
    {

        // If not ME Shared or ME Shared but not at entity context, nothing is reqd
        if (!(IsMultiEntityCompany() && GetContextLocation())) {
            return true;
        }

        $entityXML = '';
        $entInfo = GetContextLocationDetails();
        $renameArr = array('LOCATION_NO' => 'ID');
        foreach ($entInfo as $key => $val) {
            $tagName = $key;
            if (isset($renameArr[$key]) && $renameArr[$key] != '') {
                $tagName = $renameArr[$key];
            }
            $start_tag = '<' . $tagName . '>';
            if (isset($val) && $val != '') {
                $valTag = XMLUtils::xmlSpecialChars($val);
            } else {
                $valTag = '<undef/>';
            }
            $end_tag = '</' . $tagName . '>';
            $entityXML .= $start_tag . $valTag . $end_tag . "\n        ";
        }
        $entityXML = isl_rtrim($entityXML, "        ");
        if ($entityXML != '') {

            $xml = str_replace("</COMPANY>", "</COMPANY>\n    <ENTITY_INFO>\n        $entityXML   </ENTITY_INFO>", $xml);
        }

        return $xml;
    }

    /**
     * @param string $xml
     * @param bool   $iscustomdoc
     *
     * @return mixed|string
     */
    function ProcessXMLRoot(&$xml, $iscustomdoc)
    {

        // we only want to do this replacement if we are going to print via a print_layout and,
        // not an editor_layout
        // editor layouts are going to have a problem when printing multiples.
        if ($this->XSL_Template_Type != 'entity_edit_layout') {
            // make sure DOC/DOX templates won't be processed here but XSL will
            if (!$iscustomdoc) {
                // we only want to do this replacement if we are going to print via a print_layout and not an editor_layout
                // editor layouts are going to have a problem when printing multiples.
                $xml = "<DOCUMENT>" . $xml . "</DOCUMENT>";
                $xml = str_replace("<ROOT", "<OLDROOT", $xml);
                $xml = str_replace("</ROOT", "</OLDROOT", $xml);
            }
        }

        return $xml;
    }


    /**
     * @param array $values
     * @param bool  $iscustomdoc
     *
     * @throws Exception
     */
    function ProcessMultiCurrencyLineEntriesForBlob(&$values, $iscustomdoc = false)
    {
        global $kSOid, $kPOid, $kINVid;;

        $modArray = array('so' => $kSOid, 'po' => $kPOid, 'inv' => $kINVid);
        $precisionFields = array('so' => 'NUMDEC_SALE', 'po' => 'NUMDEC_PUR', 'inv' => 'NUMDEC_STD');
        $modEntityArray = array('so' => 'sodocument', 'po' => 'podocument', 'inv' => 'invdocument');

        GetModulePreferences($modArray[$this->mod], $prefs);
        $appPrecision = ($prefs['ITEMPRECISION']) ?: 2;

        if (isset($values['SUBTOTALS'])) {
            global $gManagerFactory;
            /**
             * @var DocumentManager $docMgr
             */
            $docMgr = $gManagerFactory->getManager($modEntityArray[$this->mod]);
            if (!$iscustomdoc) {
                $docMgr->subtotalsForBlob($values);
            } else {
                $docMgr->subtotalsForCustomDocBlob($values);
            }
        }
        for ($i = 0; $i < count($values['ENTRIES']); $i++) {
            if ($values['ENTRIES'][$i]['ITEM'][$precisionFields[$this->mod]] != '') {
                $itemPrecision = $values['ENTRIES'][$i]['ITEM'][$precisionFields[$this->mod]];
            } else {
                $itemPrecision = $appPrecision;
            }

            $values['ENTRIES'][$i]['UIPRICE'] = $values['ENTRIES'][$i]['TRX_PRICE'];
            $values['ENTRIES'][$i]['UIVALUE'] = $values['ENTRIES'][$i]['TRX_VALUE'];

            $values['ENTRIES'][$i]['UIPRICE'] = ibcmul($values['ENTRIES'][$i]['UIPRICE'], '1', $itemPrecision, false);
            $values['ENTRIES'][$i]['UIVALUE'] = ibcmul($values['ENTRIES'][$i]['UIVALUE'], '1', 2, false);

            // exposing these fields to the toolbar
            $values['ENTRIES'][$i]['PRICE'] = ibcmul($values['ENTRIES'][$i]['PRICE'], '1', $itemPrecision, true);
        }
    }

    /**
     * @param array $field
     */
    function ShowExpandedConvertedFrom($field)
    {

        //$mode = $this->tempfields['COPYMODE'];
        $copyfromfield = $this->tempfields['COPYFROM'];

        ?>
        <table border="1" cellpadding=2 cellspacing=0>
        <tr>
            <td>
                <table cellpadding=1>
                    <tr>
                        <td nowrap><FONT size="1">Convert From</font></td>
                        <td NOWRAP valign="middle">
                            <? parent::ShowSimpleFieldValue($field); ?>
                        </td>
                    </tr>
                    <tr>
                        <td nowrap colspan=2 align=center><FONT size="1"><b>Or</b></font></td>
                    </tr>
                    <tr>
                        <td nowrap><FONT size="1">Copy From</font></td>
                        <td NOWRAP valign="middle">
                            <? parent::ShowSimpleFieldValue($copyfromfield); ?>
                        </td>
                    </tr>
                </table>
            </td>
        </tr></table><?
    }

    /**
     * @param array $field
     */
    function ShowTaggedFieldValue($field)
    {
        ?>
        <TABLE cellpadding="0" cellspacing="0" border="0">
            <TR>
                <TD valign="middle" nowrap>
                    <INPUT type="hidden" name="<? echo $field['varname']; ?>" value="<? echo $field['value']; ?>">
                    <b>
                        <font id="<? echo $field['path'] . $field['layer']; ?>" face="Verdana, Arial, Helvetica">
                            <? echo $field['value']; ?>
                        </font>
                    </b>
                </TD>
            </TR>
        </TABLE>
        <?
    }

    /**
     *
     */
    function ShowHiddenFields()
    {
        $obj = Request::$r->GetCurrentObject();
        ?>
        <INPUT type="hidden" name="_entid" value="<? echo Request::$r->_entid; ?>">
        <INPUT type="hidden" name="_date" value="<? echo Request::$r->_date; ?>">
        <INPUT type="hidden" name="_copymode" value="<? echo Request::$r->_copymode; ?>">
        <INPUT type="hidden" name="_subtotalCount" value="<? echo Request::$r->_subtotalCount; ?>">
        <?
        if ($obj['_invTransferOutWarning']) { ?>
            <INPUT type="hidden" name=".invTransOutWarn" value="<? echo $obj['_invTransferOutWarning']; ?>">
            <?
        } ?>
        <?
        Editor::ShowHiddenFields();

        $rec = Request::$r->GetCurrentObject();
        foreach ($rec['ENTRIES'] as $r) {
            $lineno = $r['LINE_NO'];
            $quantity = $r['QUANTITY'];
            ?>
            <INPUT type="hidden" name="_inquantity(<?= $lineno ?>)" value="<?= $quantity ?>">
            <?
        }
        // loop, building our hidden array
        //epp("TIMINGS: COLLECT->$coll_time");

    }


    /**
     * @param array  $_params
     * @param string $disable
     */
    function ShowDoButtons($_params, $disable = "")
    {
        $cssClass = $this->isQuixote ? 'btn btn-primary' : 'nosavehistory';

        if ($this->_stateEditable) {
            $dobutton = 'Post';
            $doaction = 'save';
            ?>
            <INPUT class="<?= $cssClass; ?>" type="button" name="savebutton" value="<? echo $dobutton; ?>"
                   onclick="document.forms[0].elements['_do'].value = 'edit';
                           document.forms[0].elements['_state'].value = 'showedit';
                           document.forms[0].<? echo Editor_Action; ?>.value = '<? echo $doaction; ?>';
                           if ( BeforeSubmit() && beforeSubmitJS() ) { document.forms[0].submit() };"
                   disableonsubmit="true">
            <?
        } else {
            $dobutton = $_params['dobutton'];
            $doaction = $_params['doaction'];


            if ($dobutton) { ?>
                <INPUT id="savebuttid" type="button" name="savebutton" class="<?= $cssClass; ?>"
                       value="<? echo $dobutton; ?>"
                       onclick="document.forms[0].<? echo Editor_Action; ?>.value = '<? echo $doaction; ?>';if ( beforeSubmitJS() && BeforeSubmit() ) { document.forms[0].submit() };"
                       disableonsubmit="true">
                <?
            }
        }
    }


    /**
     * @param array $_params
     *
     * @return bool
     */
    function ShowDraftButtons($_params)
    {
        if ($this->showDraft) {
            Editor::ShowDraftButtons($_params);
        }
        return true;
    }


    /**
     * @param array $_params
     */
    function ShowSaveAndNewButtons($_params)
    {

        $saveandnewbutton = $_params['saveandnewbutton'];
        $saveandnewaction = $_params['saveandnewaction'];

        $cssClass = $this->isQuixote ? 'btn btn-primary' : 'nosavehistory';

        if ($saveandnewbutton) { ?>
            <INPUT type="hidden" name="after" value=''>
            <INPUT id="saveandnewbuttid" class="<?= $cssClass; ?>" type="button" name="saveandnewbutton"
                   value="<?= $saveandnewbutton ?>"
                   onclick="document.forms[0].<? echo Editor_Action; ?>.value = '<?= $saveandnewaction ?>';document.forms[0].after.value = 1; if( beforeSubmitJS() && BeforeSubmit()) { document.forms[0].submit(); };"
                   disableonsubmit="true">
            <?
        }
    }


    /**
     * @param array $_params
     */
    function ProcessSaveAction(&$_params)
    {
        /**
         * @var URLS  $gURLs
         */
        global $gURLs;
        $entityMgr = $this->GetManager($_params['entity']);

        $objId = Request::$r->{Globals::$g->kId};
        $obj =& Request::$r->GetCurrentObject();

        // Setting the request objects as part of the $obj array that would be used by the Add/Set of the Managers
        $obj['_kNoWarn'] = Request::$r->_kNoWarn;
        $obj['_kNoDupl'] = Request::$r->_kNoDupl;
        $obj['_do'] = Request::$r->_do;
        $obj['_mod'] = Request::$r->_mod;
        $obj['_invTransferOutWarning'] = Request::$r->_invTransOutWarn;
        /**
         * @var DocumentManager $entityMgr
         */
        $entityMgr->setWarningValidation();
        $ok = $this->PrepareInputValues($_params, $obj);

        $ok = $ok && $this->prepareObjectForSave($obj);
        $ok = $ok && $this->validatePlatformData($obj);

        if ($this->_stateEditable) {
            $ok = $ok && $entityMgr->PartialSet($obj);
        } else {
            $obj = $this->DoRefreshAction($_params, $obj);
            $ok = $ok && $entityMgr->set($obj);
        }
        $entityDesc = $_params['entityDesc'];
        if (!$ok) {
            global $gErr;
            if ($gErr->hasWarnings()) {
                $this->warningmessage = true;
                $this->state = $this->kEditWarningState;
                if (!util_isPlatformDisabled()) {
                    $entityMgr->getRelationships($obj, false, false, false, true);
                    $this->setPlatformData($obj);
                }

            }
            $warnmessage = HasErrors();
            if ($warnmessage) {
                $gErr->addError(
                    "BL03000021", __FILE__ . ":" . __LINE__,
                    _("Updating $entityDesc '$objId' failed")
                );
                $this->state = $this->kErrorState;
            } else {
                $obj =& Request::$r->GetCurrentObject();
                Request::$r->SetCurrentObject($obj);
                Request::$r->_action = $this->kSaveAction;
                $this->state = $this->kShowEditState;
            }
        } elseif ($this->GetPreference($_params, "Update.RequireConfirmation")) {
            $confirmation = _("The $entityDesc was saved successfully");
            $this->SetMessageWithObject($confirmation, $obj);
            $this->state = $this->kConfirmState;
        } elseif ($gURLs->HasReturnPath()) {
            $this->state = $this->kGoBackState;
        } elseif ($_params['popup']) {
            $this->state = $this->kCloseState;
        } else {
            $this->state = $this->kGoHomeState;
        }
    }


    function ShowGeneralHiddenFields()
    {
        parent::ShowGeneralHiddenFields(); ?>
        <INPUT type="hidden" name="_kNoWarn" value="<? echo Request::$r->_kNoWarn; ?>">
        <INPUT type="hidden" name="_kNoDupl" value="<? echo Request::$r->_kNoDupl; ?>">
        <INPUT type="hidden" name=".newWhseAdded" value="">
        <INPUT type="hidden" name=".index" value="">
        <INPUT type="hidden" name=".draftmode" value=""><?
    }


    /**
     * @param array $docparmrec
     * @param array $_params
     */
    function ChangeContactLabels($docparmrec, &$_params)
    {
        //	Set the Contact Labels from the doc par information here
        $pagecount = count($_params['pages']);

        for ($i = 0; $i < $pagecount; $i++) {
            if ($_params['pages'][$i]['title'] == "Header") {

                $fieldcount = count($_params['pages'][$i]['fields']);

                for ($j = 0; $j < $fieldcount; $j++) {
                    if (is_array($_params['pages'][$i]['fields'][$j]['columns'] ?? null)) {
                        foreach ($_params['pages'][$i]['fields'][$j]['columns'] as $key => $field) {
                            if ($field['path'] == 'BILLTO.CONTACTNAME') {
                                $_params['pages'][$i]['fields'][$j]['fullname'] = $docparmrec['CONTACTTITLE1'] . ' Contact';
                                $_params['pages'][$i]['fields'][$j]['columns'][$key]['JSFullname'] = $docparmrec['CONTACTTITLE1'] . ' Contact';
                            }
                            if ($field['path'] == 'SHIPTO.CONTACTNAME') {
                                $_params['pages'][$i]['fields'][$j]['fullname'] = $docparmrec['CONTACTTITLE2'] . ' Contact';
                                $_params['pages'][$i]['fields'][$j]['columns'][$key]['JSFullname'] = $docparmrec['CONTACTTITLE2'] . ' Contact';
                            }
                        }
                    }
                }
            }
        }
    }

    /**
     * @return int
     */
    function LookupAppPrecision()
    {

        global $kINVid, $kSOid, $kPOid;

        $modArray = array('so' => $kSOid, 'po' => $kPOid, 'inv' => $kINVid);
        GetModulePreferences($modArray[$this->mod], $prefs);

        return ($prefs['ITEMPRECISION']) ?: 2;
    }


    /**
     * @param array  $values
     * @param string $key
     *
     * @return mixed
     * @throws Exception
     */
    function _PrepSalesforceValues($values, $key)
    {
        global $gManagerFactory;
        include_once 'ObjectStoreManager.cls';

        // gets the values for the mcp enabled companies.
        $mcpsubscribed = IsMCPSubscribed();
        $sfismcp = GetPreferenceForProperty('38.SFDC', 'SFORCEISMCP');

        // get the values out of the object store
        $objstore = new ObjectStoreManager();
        $sfdcvalues = $objstore->get($key);
        $new = $values;

        // need to convert the custvendid.

        $new['CUSTVENDID'] = $sfdcvalues['OBJECTDATA']['CUSTOMERID'] ?: $values['CUSTVENDID'];
        $new['PONUMBER'] = $sfdcvalues['OBJECTDATA']['NAME'] ?: $values['PONUMBER'];
        $new['MESSAGE'] = $sfdcvalues['OBJECTDATA']['DESCRIPTION'] ?: $new['MESSAGE'];
        $new['SFORCEID'] = $sfdcvalues['OBJECTDATA']['SFORCEID'] ?: $new['SFORCEID'];
        $new['SFORCEKEY'] = $sfdcvalues['OBJECTDATA']['SFORCEKEY'] ?: $new['SFORCEKEY'];
        //Get Template definition
        $docType = $sfdcvalues['OBJECTDATA']['DOCTYPE'];
        $docparMgr = $gManagerFactory->getManager('documentparams');
        $_docpar = $docparMgr->GetLatestRaw($docType);
        $_docpar = $_docpar[0];

        // getting the currency and exchange rate from sales force and populate in the sales document.
        if ($mcpsubscribed && $sfismcp == 'true' && $sfdcvalues['OBJECTDATA']['CURRENCYISOCODE']) {
            $new['CURRENCY'] = $sfdcvalues['OBJECTDATA']['CURRENCYISOCODE'];
        }
        //Copy Sforce
        if (!$new['SFORCEID'] && $new['RECORDNO']) {            //
            $subscription = $gManagerFactory->getManager('imssubscription');
            $new['SFORCEID'] = $subscription->GetExternalId($new['RECORDNO'], 'SODOCUMENTOPP', 'SFORCE');
        }

        //To get SFDC Opportunity Line Items
        include_once 'SforceSynchronizer.cls';
        $sfSync = new SforceSynchronizer();

        // Collect custom field details for SF Opportunity object
        $iaobj = 'SODOCUMENT';
        $iaobjdoctype = $new['DOCPARID'];
        $sfobj = 'Opportunity';
        $sfobjkey = 'Id';
        $sfobjval = $new['SFORCEID'];
        $sfSync->GetSFCustomFieldValues($iaobj, $iaobjdoctype, $sfobj, $sfobjkey, $sfobjval, $new, true);
        //eppp_p($new);

        $custMgr = $gManagerFactory->getManager('customer');

        $custParams = array(
            'selects' => array(
                'CUSTMESSAGEID',
                'SHIPTO.CONTACTNAME',
                'BILLTO.CONTACTNAME',
                'CREDITLIMIT',
                'TOTALDUE',
            ),
            'filters' => array(array(
                array('CUSTOMERID', '=', $new['CUSTVENDID'])
            )),
        );

        $custInfo = $custMgr->GetList($custParams);
        $this->sfcrlimit = $custInfo[0]['CREDITLIMIT'];
        $this->sftotdue = $custInfo[0]['TOTALDUE'];

        if ($new['MESSAGE'] == '' || $sfSync->_preferences['SFORCEPRICINGOPT'] != SFORCEPRICING) {

            $custMsgMgr = $gManagerFactory->getManager('custmessage');
            $params = array(
                'selects' => array(
                    'MESSAGE',
                ),
                'filters' => array(array(
                    array('MESSAGEID', '=', $custInfo[0]['CUSTMESSAGEID']),
                    array('STATUS', '=', 'active'),
                )),
            );

            $custMsgInfo = $custMsgMgr->GetList($params);
            if ($new['MESSAGE'] == '' && isset($custMsgInfo[0]['MESSAGE'])) {
                $new['MESSAGE'] = $custMsgInfo[0]['MESSAGE'];
            }
        }

        if ($sfSync->ShowOppLineItems()) {

            // Collect custom field details for SF Opportunity Product object
            $iaobj = 'SODOCUMENTENTRY';
            $iaobjdoctype = $new['DOCPARID'];
            $ret = $sfSync->GetFieldMapStruct($iaobj, $iaobjdoctype);
            $fields = $ret['fields'];
            $fieldDetails = $ret['fieldDetails'];

            //Get Opportunity Product List
            $fldArr = (is_array($fields) && count($fields)) ? $fields : array();
            $ProductItems = $sfSync->GetOppProductItems($fldArr);

            $count = 0;
            //only if Opportunity have Products
            if ($ProductItems) {
                /** @var ItemManager $itemMgr */
                $itemMgr = $gManagerFactory->getManager('item');

                //Handle SFDC Pricing Option
                if ($sfSync->_preferences['SFORCEPRICINGOPT'] == SFORCEPRICING) {
                    $this->sfdcPricing = 'true';
                } else {
                    //Handles Intacct Pricing
                    $_shipto = $custInfo[0]['SHIPTO.CONTACTNAME'];
                    $_billto = $custInfo[0]['BILLTO.CONTACTNAME'];
                    $_date = GetCurrentDate();
                    $currency = $new['CURRENCY'];
                }

                $pricingHandler = Globals::$g->gManagerFactory->_getObjectInstance('PricingHandler');
                /** @noinspection PhpUndefinedVariableInspection */
                $priceParams = $pricingHandler->PrepParams($new['CUSTVENDID'], $_billto, $_shipto, $_date, $this->mod);

                //Get default warehouse, if it is set
                $docpar = $this->GetBaseDocPar();
                if ($docpar['WAREHOUSESELMETHOD'] == 'Use the default warehouse') {
                    GetUserPreferences($upref, 'DEFAULT_WAREHOUSE');
                    $upref_docpar_whse = $upref['DEFAULT_WAREHOUSE'];
                    if ($upref_docpar_whse == '' && $docpar['DEFAULT_WAREHOUSE'] != '') {
                        $upref_docpar_whse = $docpar['DEFAULT_WAREHOUSE'];
                    }
                    if ($upref_docpar_whse != '') {
                        $whse_name = QueryResult(array("select NAME from ICWAREHOUSE where cny# = :1 and LOCATION_NO = :2", GetMyCompany(), $upref_docpar_whse));
                        $whse_location_name = $upref_docpar_whse . '--' . $whse_name[0]['NAME'];
                    }
                }
                //Autofill the value for primary dimensions 'CUSTOMER' for SODOCUMENT
                $soDocEntryMgr = $gManagerFactory->getManager($this->mod . "documententry");
                $dimcolumns = $soDocEntryMgr->GetDimensionFields();
                $custDimEnabled = false;
                foreach ($dimcolumns as $dimcolumn) {
                    if ($dimcolumn['path'] == 'CUSTOMERID') {
                        $custDimEnabled = true;
                    }
                }

                $uomgrpMgr = $gManagerFactory->getManager('uom');

                foreach ( $ProductItems as $ProductItem) {
                    //Get Item Unit Measurements
                    $ItemData = $itemMgr->Get($ProductItem['PRODUCTCODE']);
                    if ($ItemData) {
                        $uom = $uomgrpMgr->get($ItemData['UOMGRP']);
                        $new['ENTRIES'][$count]['UNIT'] = $uom['OEUOM'];
                        $new['ENTRIES'][$count]['ITEM']['UOMGRPKEY'] = $uom['RECORDNO'];
                        $new['ENTRIES'][$count]['ITEMID'] = $ProductItem['PRODUCTCODE'];
                        $new['ENTRIES'][$count]['MEMO'] = $ProductItem['DESCRIPTION'];
                        $new['ENTRIES'][$count]['UIQTY'] = $ProductItem['QUANTITY'] ?? 1;
                        $new['ENTRIES'][$count]['ITEMDESC'] = $ProductItem['NAME'];
                        $new['ENTRIES'][$count]['ITEMTERM'] = $ItemData['TERMPERIOD'];
                        $new['ENTRIES'][$count]['TERMPERIOD'] = $ItemData['TOTALPERIODS'];

                        if ($this->sfdcPricing == 'true') {
                            $saleprice = $ProductItem['UNITPRICE'];
                            $new['ENTRIES'][$count]['RETAILPRICE'] = $ProductItem['LISTPRICE'];
                        } else {
                            //Intacct Pricing Rule applied
                            /** @noinspection PhpUndefinedVariableInspection */
                            $price = $pricingHandler->SuggestPrice(
                                $priceParams, $new['ENTRIES'][$count]['ITEMID'],
                                $ItemData['PRODUCTLINEID'], $new['ENTRIES'][$count]['UIQTY'], $_docpar, $currency
                            );
                            if (!$price) {
                                $price = "0.00";
                            }

                            $sfactor = 1;
                            // Find the OE Conv factor
                            foreach ( $uom['ENTRIES'] as $unitInfo) {
                                if ($unitInfo['UNIT'] == $uom['OEUOM']) {
                                    /** @noinspection PhpUndefinedVariableInspection */
                                    $sfactor = $uomInfo['CONVFACTOR'];
                                }
                            }

                            // by default use sfactor as 1
                            if (!$sfactor) {
                                $sfactor = 1;
                            }

                            //Calculate price based on Sales Unit  Factor
                            $saleprice = $price * $sfactor;
                            $new['ENTRIES'][$count]['RETAILPRICE'] = $saleprice;
                        }

                        if ($mcpsubscribed) {
                            $new['ENTRIES'][$count]['TRX_PRICE'] = $saleprice;
                        } else {
                            $new['ENTRIES'][$count]['UIPRICE'] = $saleprice;
                        }

                        $new['ENTRIES'][$count]['REVRECSTARTDATE'] = $ProductItem['SERVICEDATE'];
                        $new['ENTRIES'][$count]['REVRECENDDATE'] = $ProductItem['SERVICEENDDATE__C'];
                        /** @noinspection PhpUndefinedVariableInspection */
                        $new['ENTRIES'][$count]['WAREHOUSE']['LOCATION_NO'] = $whse_location_name;
                        if ($custDimEnabled) {
                            $new['ENTRIES'][$count]['CUSTOMERID'] = $new['CUSTVENDID'];
                        }

                        // Append SF opportunity product custom fields to intacct document entry line
                        $sfSync->GetOppProductCustomFieldsForEntry(
                            $fieldDetails,
                            $ProductItem,
                            $new['ENTRIES'][$count]
                        );
                        ++$count;
                    }
                } // End of foreach
            }
        }
        //if mcp is enabled and trx currency is different than base currency
        if ($this->_ismcpEnabled) {
            $new['EXCHRATEDATE'] = GetCurrentDate();
            $basecurr = GetBaseCurrency();
            if ($new['CURRENCY'] != $basecurr) {
                $exchTypeMgr = $gManagerFactory->getManager('exchangeratetypes');
                $exchRateMgr = $gManagerFactory->getManager('exchangerate');

                $new['EXCH_RATE_TYPE_ID'] = $_docpar['EXCH_RATE_TYPE_ID'];
                //Get default Exchange rate for company level
                $rtype = $exchTypeMgr->GetDefaultExchangeRateType();
                if ($rtype[0]['ID'] != '-1') {
                    $new['EXCH_RATE_TYPE_ID'] = $rtype[0]['ID'];
                }

                if ($new['EXCH_RATE_TYPE_ID'] == '-1' || $new['EXCH_RATE_TYPE_ID'] == '') {
                    $new['EXCHRATE'] = $exchRateMgr->GetIntacctExchangeRate($new['CURRENCY'], $basecurr, $new['EXCHRATEDATE']);
                } else {
                    $new['EXCHRATE'] = $exchRateMgr->GetTrxExchangeRateByTypeID($new['EXCH_RATE_TYPE_ID'], $new['CURRENCY'], $basecurr, $new['EXCHRATEDATE']);
                }
            }
        }

        return $new;
    }


    /**
     * @var string $kDeriveDocumentAction
     */
    var $kDeriveDocumentAction = 'derive';


    /**
     * @return bool
     */
    function CanEdit()
    {
        if (parent::CanEdit()) {
            $this->MatchTemplates($this->_params, array('path' => 'STATE'), $_state);
            $nonEditableStates = array("Converted", "In Progress", "Submitted", "Partially Approved", "Approved");
            foreach ( $_state as $i => $x) {
                if (in_array($_state[$i]['value'], $nonEditableStates)) {
                    return false;
                }
            }
            return true;
        }
        return false;
    }


    /**
     * @param string $entity
     *
     * @return EntityManager
     * @throws Exception
     */
    function GetManager($entity)
    {
        $docid = Request::$r->_r;
        if ($this->dt == '' && $docid != '') {
            $this->dt = GetDocumentType($docid);
            if ($this->dt != '') {
                Request::$r->_dt = $this->dt;
            }
        }
        $entManager = Globals::$g->gManagerFactory->getManager($entity, false, array( 'DOCTYPE' => $this->dt));
        return $entManager;
    }


    // function ShowFormButtons($_params)

    /**
     * Displays action buttons in banner.
     * Added function for recurring document support to add the repeat button.
     * Repeat button is only shown when state is 'showedit'
     *
     * @param   array $_params
     * @param   bool  $isApprovalEnabled added to show or hide approve/decline buttons
     *
     */
    function ShowFormButtons($_params, $isApprovalEnabled = false)
    {
        $_params = $_params['buttons'];
        //$this->ShowApproveButtons($_params);
        if ($isApprovalEnabled) {
            $this->ShowSubmitButtons($_params);
            if ($this->showDraft) {
                $this->ShowContinueButtons($_params);
            }
        } else {
            $this->ShowDoButtons($_params);
            $this->ShowSaveAndNewButtons($_params);
            $this->ShowContinueButtons($_params);
        }
        $this->ShowDraftButtons($_params);
        $this->ShowDeliverButton($_params);
        $this->ShowCopyButtons($_params);

        /**
         * @var Security $gSecurity
         */
        global $gSecurity;
        $mod = $this->getRequestModule();
        $parentop = $gSecurity->GetListerOperationID($this->_params['entity'], $mod);
        $children = GetPagePermissions($parentop);
        $childrenverbs = array_keys($children);
        if (in_array('edit', $childrenverbs)
            && $this->CanEdit()
        ) {
            $this->ShowEditButtons($_params, $children['edit']);
        }

        if (!$this->showDraft && !Request::$r->_popup) {
            $_sess = Session::getKey();
            $opv = GetOperationId($this->mod . '/lists/' . $this->mod . 'recurdocument/edit');

            if ($_params['state'] != $this->kShowNewState && $opv != '-1' && CheckAuthorization($opv, 1)) {
                ?>
                <script>
                    var mod = '<?= $this->mod ?>';
                    var dt = '<?= $this->dt ?>';

                    function handleRepeat() {
                        var form = document.forms[0];
                        var msg = 'Pressing repeat button will take you to the recurring transaction \nscreen ' +
                            'and will not save any changes to this existing document. \n\nDo you want to continue?';
                        if (confirm(msg)) {
                            form.action = 'editor.phtml?.op=<? echo $opv; ?>' +
                                '&.dt=' + dt + '&.it=' + mod + 'recurdocument&.sess=<? echo urlencode($_sess);?>' +
                                '&.action=copy&.from=document';

                            form._it.value = mod + 'recurdocument';
                            form._action.value = 'copy';
                            form.elements['.r'].value = '';
                            form._do.value = 'edit';
                            form._state.value = 'showedit';
                            if (BeforeSubmit()) {
                                form.submit();
                            }
                        }
                    }
                </script>
                <INPUT class="nosavehistory"
                       type="button"
                       name="recurbutton"
                       value="Repeat"
                       onclick="handleRepeat();">
                <?
            }
        }

        $this->ShowCancelButtons($_params);
        $this->ShowDeleteButtons($_params);

    }


    /**
     * @param array $_params
     *
     * @return bool
     */
    function ShowSubmitButtons(/** @noinspection PhpUnusedParameterInspection */ $_params)
    {
        // Sub classes to implement this API
        return true;
    }

    /**
     * @param array $_params
     */
    function ShowContinueButtons($_params)
    {
        $scontinuebutton = $_params['scontinuebutton'];
        $scontinueaction = $_params['scontinueaction'];

        if ($this->showDraft) {
            $scontinuebutton = "Draft & Continue";
        }

        if ($scontinuebutton) { ?>
            <INPUT type="button" name="scontinuebutton" class="nosavehistory" value="<? echo $scontinuebutton; ?>"
                   onclick="document.forms[0].<? echo Editor_Action; ?>.value = '<? echo $scontinueaction; ?>';BeforeSubmit();document.forms[0].submit();"
                   disableonsubmit="true">
            <?
        }
    }


    /**
     * @param array $_params
     *
     * @throws Exception
     */
    function ProcessSaveContinueAction(&$_params)
    {
        $_params['_iscontinue'] = true;

        global $gErr;
        $obj =& Request::$r->GetCurrentObject();

        if ($this->state == $this->kShowNewState) {
            $obj['_isdraft'] = true;
            $this->ProcessCreateAction($_params);
        } else {
            if ($obj['STATE'] == 'Draft') {
                $obj['_isdraft'] = true;
            }
            $this->ProcessSaveAction($_params);
        }

        if (!in_array($this->state, array($this->kErrorState, $this->kEditWarningState)) && !$gErr->hasWarnings()) {
            Request::$r->_currentlayer = '';
            Request::$r->_changed = 'false';
            $obj =& Request::$r->GetCurrentObject();
            $entityMgr = $this->GetManager($_params['entity']);
            EntityManager::SetByPath($obj, $entityMgr->GetKeyFieldName(), '');

            $ent = $obj['CUSTVENDID'];
            [$ent] = explode('--', $ent);

            $srcdoc = $obj['DOCPARID'] . "-" . $obj['DOCNO'];

            $op = GetOperationId($this->mod . '/lists/' . $this->mod . 'document/edit');

            Request::$r->SetCurrentObject($obj);
            $this->state = $this->kShowEditState;
            $this->SetDoneParam();

            /** @noinspection PhpUndefinedVariableInspection */
            Fwd('editor.phtml?.sess=' . $_sess . '&.r=' . urlencode($srcdoc) . '&.op=' . $op . '&_ent=' . urlencode($ent) . '&.dt=' . urlencode($this->dt) . '&_msg=' . urlencode($this->GetMessage()), $this->done);
        }
    }


    /**
     *
     */
    function SetDoneParam()
    {
        $list_op = GetOperationId($this->mod . '/lists/' . $this->mod . 'document');
        $_done = Request::$r->_done;
        $_sess = Session::getKey();
        if (isl_strstr($_done, "sforcekey") === false) {
            $this->done = 'lister.phtml?.op=' . $list_op . '&.dt=' . urlencode($this->dt) . '&.sess=' . $_sess;
        }
    }


    /**
     * While convertng document, copy parent's document date to $newDoc
     *
     * @param string[] $sourceDoc
     * @param string[] $newDoc
     * @param string[] $newDocpar
     *
     * @return bool
     */
    function GetOrigDocDate(
        /** @noinspection PhpUnusedParameterInspection */ $sourceDoc,
        /** @noinspection PhpUnusedParameterInspection */ &$newDoc,
        /** @noinspection PhpUnusedParameterInspection */ $newDocpar)
    {
        return true;
    }


    public function ShowPreLayoutInfo()
    {
        ?>

        <?
    }

    /**
     * @param string $copy
     * @param array  &$old
     *
     * @return true
     */
    protected function processCopyConvert(
        /** @noinspection PhpUnusedParameterInspection */ $copy,
        /** @noinspection PhpUnusedParameterInspection */ &$old)
    {
        return true;
    }


    /**
     * This function will decide the display of GL posting date display.
     *
     * @param   array   $docpar
     * @param   bool    &$autofill
     *
     * @return false
     */
    protected function ShowGLPostingDate(
        /** @noinspection PhpUnusedParameterInspection */ $docpar,
        /** @noinspection PhpUnusedParameterInspection */ &$autofill = false)
    {
        return false;
    }

    /**
     * Gets all fields from corresponding platform page as hidden inputs
     */
    function ShowPlatformHiddenFields()
    {

        parent::ShowPlatformHiddenFields();

        /*
         * Code to show the platform fields for subtotals
         * Get the Subtotal object name into $multiObjDefName
         */
        $multiObjDefName = $this->getSubtotalsDefName();

        $objDef = Pt_StandardUtil::getObjDef($multiObjDefName);

        $platformRels = Pt_StandardUtil::getRelationshipFields($objDef);

        if (!empty($platformRels) && !util_isPlatformDisabled()) {
            $this->MatchTemplates($this->_params, array('path' => 'SUBTOTALS'), $subtotals);
            // This will traverse parameters array in search of 'actualnumofrows' element
            $numLines = intval(util_findInArray($subtotals, 'actualnumofrows'));

            echo Pt_StandardUtil::getMultilineHiddenFields($platformRels, $numLines, 'SUBTOTALS');
        }
    }

    /**
     * we set the Current multiline path which can be useful to return when
     * there are multiple multiline displays available.
     *
     * @param null|string $path Path of the current object that is being drawn
     */
    function setMultilinePath($path = NULL)
    {
        self::$currentMultilinePath = $path;
    }

    /**
     * Function to get the subtotal entity for current record
     *
     * @return string Subtotal entity
     */
    function getSubtotalsDefName()
    {
        return $this->mod . 'documentsubtotals';
    }

    /**
     * Function to cache the Subtotal Dimensions with the relationship keys instead
     * with field names as EditorGetSubtotals call removes the Relationshipkeys :(
     *
     * @param array $obj Current Record that is being Edited, Duplicated or Viewed
     */
    function cacheSubtotalDimensions($obj)
    {

        if (util_isPlatformDisabled()) {
            return;
        }

        /*
         * Get the Subtotal object name into $multiObjDefName
         */
        $multiObjDefName = $this->getSubtotalsDefName();
        $objDef = Pt_StandardUtil::getObjDef($multiObjDefName);
        $this->pt_relationships = Pt_StandardUtil::getRelationshipFields($objDef);
        $rel_map = IADimensions::getRelationShipMap($multiObjDefName);
        $dimCache = array();
        foreach ($this->pt_relationships as $fld) {
            $dim_key = array_search(isl_strtoupper($fld->getFieldName()), $rel_map);
            foreach ($obj['SUBTOTALS'] as $subtotal) {
                if (in_array($subtotal['DESCRIPTION'], array('TOTAL', 'SUBTOTAL'))) {
                    continue;
                }
                $dimCache[$dim_key][$subtotal['DESCRIPTION']] = $subtotal[$dim_key];
            }
        }
        $this->cust_dim_cache = $dimCache;
    }

    /**
     * Function to restore the cached custom dimenison relations after the EditorGetSubtotals
     * call is completed
     *
     * @param array $obj Current Record that is being Edited, Duplicated or Viewed
     */
    function restoreSubtotalDimensions(&$obj)
    {

        if (util_isPlatformDisabled()) {
            return;
        }
        /*
         * Get the Subtotal object name into $multiObjDefName
         */
        $multiObjDefName = $this->getSubtotalsDefName();
        $rel_map = IADimensions::getRelationShipMap($multiObjDefName);
        foreach ($this->pt_relationships as $fld) {
            $dim_key = array_search(isl_strtoupper($fld->getFieldName()), $rel_map);
            foreach ($obj['SUBTOTALS'] as &$subtotal) {
                if (in_array($subtotal['DESCRIPTION'], array('TOTAL', 'SUBTOTAL'))) {
                    continue;
                }
                $subtotal[$dim_key] = $this->cust_dim_cache[$dim_key][$subtotal['DESCRIPTION']];
            }
        }
    }

    /**
     * Function to merge the Custom Dimensions with the current Layout Parameters
     *
     * @param array $columns Columns to which the Custom dimensions will be merged to
     */
    function mergeSubtotalCustomDimensions(&$columns)
    {

        if (util_isPlatformDisabled()) {
            return;
        }

        $mgr = $this->GetManager($this->getSubtotalsDefName());
        $customEntity = $mgr->GetCustomComponentsEntity();

        $platformDef = Pt_StandardUtil::getObjDef($customEntity);
        $nodes = array();

        if ($platformDef) {
            $platformRels = Pt_StandardUtil::getRelationshipFields($platformDef);
            foreach ($platformRels as $relField) {
                if ( ( $relDef = $relField->getRelationshipDef() ) && $relDef->isGLDimension() ) {

                    $nodes[] = array(
                        'fullname'            => $relField->getUIField()->__toString(),
                        'path'                => isl_strtoupper($relField->getUIField()->getFieldName()),
                        'type'                => array(
                            'ptype' => 'text',
                        ),
                        'readonly'            => (IsMultiEntityCompany() && !GetContextLocation()),
                        'iscustomgldimension' => true,
                        'relfield'            => $relField,
                    );
                }
            }
            $columns = INTACCTarray_merge($columns, $nodes);
        }
    }


    /**
     * @param string $ownerobject
     *
     * @return string
     */
    function GetCustomOwnerObject(/** @noinspection PhpUnusedParameterInspection */ $ownerobject)
    {
        die("Override this function, please!");
    }
}
