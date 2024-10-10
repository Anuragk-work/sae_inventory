<?php

/* File header
*	FILE: ICCycleCountFormEditor.cls
*	AUTHOR: shreerajath Hebbar <shreerajath.hebbar@sage.com>
*	DESCRIPTION: ICCycleCountFormEditor is editor class
*
*	(C) 2020, Intacct Corporation, All Rights Reserved
*
*	This document contains trade secret data that belongs to Intacct
*	Corporation and is protected by the copyright laws.  Information
*	herein may not be used, copied or disclosed in whole or in part
*	without prior written consent from Intacct Corporation.
*/

class ICCycleCountFormEditor extends FormEditor
{

    const ALL = "ALL";
    const ALL_EXCEPT_SOME  = "ALL_EXCEPT_SOME";
    const NONE_EXCEPT_SOME = "NONE_EXCEPT_SOME";

    const STATE_NOTSTARTED = 'IA.NOT_STARTED';
    const STATE_INPROGRESS = 'IA.IN_PROGRESS';
    const STATE_COUNTED    = 'IA.COUNTED';
    const STATE_RECONCILED = 'IA.RECONCILED';
    const STATE_VOIDED     = 'IA.VOIDED';

    const STATE_NOTSTARTED_VALUE = 'Not Started';
    const STATE_INPROGRESS_VALUE = 'In Progress';
    const STATE_COUNTED_VALUE    = 'Counted';
    const STATE_RECONCILED_VALUE = 'Reconciled';
    const STATE_VOIDED_VALUE     = 'Voided';

    //Line stated
    const LINE_STATE_SKIPPED    = 'Skipped';

    /**
     * @var string $kSaveContinueAction
     */
    var $kSaveStartCountAction = 'savestartcount';

    /**
     * @var string $kSaveContinueAction
     */
    var $kListerStartCountAction = 'listerstartcount';

    /**
     * @var string $kSaveContinueAction
     */
    var $kSaveCompleteAction = 'savecomplete';

    /**
     * @var string $kSaveContinueAction
     */
    var $kPostAdjustmentAction = 'postadjustment';

    /**
     * @var string $kSaveContinueAction
     */
    var $kVoidCountAction = 'voidcount';


    /**
     * @var string $kSaveContinueAction
     */
    var $kSaveandNew = 'saveandnew';

    /**
     * @var string $kSaveContinueAction
     */
    var $kUpdateQOHAction = 'updateqoh';

    /**
     * ICCycleCount specific tokens
     * @var array
     */
    private $icCycleCountTokens = [ 'IA.NOT_STARTED', 'IA.IN_PROGRESS', 'IA.COUNTED', 'IA.RECONCILED', 'IA.VOIDED', 'IA.QOH_AS_OF_COUNT_START',
                                    'IA.ONE_OR_MORE_ITEMS_FROM_THIS_COUNT_ARE_SKIPPED', 'IA.EDIT', 'IA.EXPORT_WORKSHEET', 'IA.EXPORT_COUNT_REPORT',
                                    'IA.DONE', 'IA.SAVE_AND_CONTINUE', 'IA.CANCEL', 'IA.UPDATE_QUANTITY_ON_HAND', 'IA.START_COUNT', 'IA.COMPLETE_COUNT',
                                    'IA.POST_ADJUSTMENT', 'IA.VOID_COUNT', 'IA.PRINT_WORKSHEET', 'IA.CYCLE_COUNT_DIMENSIONS','IA.NOT_COUNTED','IA.SKIPPED'];

     /**
      * @param array $_params values array for init params
      */
    public function __construct($_params = array())
    {
        $this->additionalTokens = array_merge($this->additionalTokens, $this->icCycleCountTokens);
        parent::__construct($_params);
    }

    function InitConstants()
    {
        parent::InitConstants();

        $this->kActionHandlers[$this->kSaveStartCountAction] = array (
            'handler' => 'ProcessStartCountAction',
            'states' => array(
                $this->kShowEditState,
                $this->kEditWarningState,
                Editor_InitState
            ),
            'csrf' => true,
        );

        $this->kActionHandlers[$this->kListerStartCountAction] = array (
            'handler' => 'ProcessListerStartCountAction',
            'states' => array(
                $this->kShowEditState,
                $this->kEditWarningState,
                Editor_InitState
            ),
            'csrf' => false,
        );

        $this->kActionHandlers[$this->kSaveCompleteAction] = array (
            'handler' => 'ProcessCompleteAction',
            'states' => array(
                $this->kShowEditState,
                $this->kEditWarningState,
                Editor_InitState
            ),
            'csrf' => true,
        );

        $this->kActionHandlers[$this->kSaveandNew] = array (
            'handler' => 'ProcessSaveandNew',
            'states' => array(
                $this->kShowEditState,
                $this->kEditWarningState,
                Editor_InitState
            ),
            'csrf' => true,
        );

        $this->kActionHandlers[$this->kPostAdjustmentAction] = array (
            'handler' => 'PostAdjustmentAction',
            'states' => array(
                $this->kShowEditState,
                $this->kEditWarningState,
                Editor_InitState
            ),
            'csrf' => true,
        );

        $this->kActionHandlers[$this->kVoidCountAction] = array (
            'handler' => 'VoidCountAction',
            'states' => array(
                $this->kShowEditState,
                $this->kEditWarningState,
                Editor_InitState
            ),
            'csrf' => true,
        );

        $this->kActionHandlers[$this->kUpdateQOHAction] = array (
            'handler' => 'UpdateQOHAction',
            'states' => array(
                $this->kShowEditState,
                $this->kEditWarningState,
                Editor_InitState
            ),
            'csrf' => true,
        );
    }

    /**
     * @param string $cmd
     *
     * @return bool
     */
    protected function runAjax($cmd)
    {
        $ok = true;
        $list = null;
        $ajaxFunctions = ['loadCycleCountData', 'getCycleCountData', 'insertCycleCountEntries',
                     'updateCycleCountEntries', 'skipCycleCountEntries', 'verifySkipCycleCountEntries',
                     'removeCycleCountEntries','additionalCycleCountEntry', 'validateFIFOLIFOEntry'];

        if(in_array($cmd, $ajaxFunctions)){
            //Calculate the requestParams and pass it to the Preticulate Ajax function call. For most of the function,
            // common requestParams are present. So using common function to calculate them and use it accordingly.
            $requestParams = $this->getCycleCountRequestParams();
            $list = $this->$cmd($requestParams);
        }else if($cmd === 'itemDetailsFetch'){
            $list = $this->itemDetailsFetch();
        }else {
            $ok = parent::runAjax($cmd);
        }

        if ( ! empty($list) ) {
            echo json_encode($list);
        } else {
            // Fix for 122333: Return null to prevent JSON.parse from throwing an error
            echo json_encode(null);
        }

        return $ok;
    }

    /**
     * @return array
     */
    protected function getJavaScriptFileNames()
    {
        $jsFiles   = parent::getJavaScriptFileNames();
        $jsFiles[] = "../resources/js/iccyclecounthandler.js";
        return $jsFiles;
    }

    /**
     * Get metadata key name
     *
     * @param array &$params
     *
     * @return string
     */
    protected function getMetadataKeyName(&$params)
    {
        $entity = $params['entity'];

        if (Request::$r->_reconcile) {
            return "${entity}_reconcile_form.pxml";
        }

        return parent::getMetadataKeyName($params);
    }

    /**
     * @return string[]
     * @throws Exception
     */
    protected function getEditorGlobals()
    {
        $vars = parent::getEditorGlobals();
        //For Interim QOH activity
        $vars['itemactivityop'] = GetOperationId('inv/reports/itemactivity');
        $vars['linecountstatus'] = array();
        //Adding the ic cycle count entry status to globals for javascript.
        $icCycleCountFieldInfo = Globals::$g->gManagerFactory->getManager('iccyclecountentry')->GetEntityInfo();
        foreach ($icCycleCountFieldInfo as $icCycleCountField) {
            if ($icCycleCountField['path'] === 'LINECOUNTSTATE') {
                for ($i = 0; $i < Util::countOrZero($icCycleCountField['type']['validlabels']); $i++) {
                    $vars['linecountstatus'][strtolower(GT($this->textMap, $icCycleCountField['type']['validlabels'][$i]))] = $icCycleCountField['type']['validvalues'][$i];
                }
                break;
            }
        }
        return $vars;
    }

    /**
     * @param array $_params
     *
     * @throws Exception
     */
    protected function buildDynamicMetadata(&$_params)
    {
        parent::buildDynamicMetadata($_params);
    }
        /**
     * @param array $obj
     *
     * @return bool
     * @throws Exception
     */
    protected function mediateDataAndMetadata(&$obj)
    {
        $state = Request::$r->_state;

        if ($state != $this->kShowNewState) {
            $this->mediateDataAndMetadata_Header($obj);
            $this->mediateDataAndMetadata_Entries($obj);
        }

        //Specifically added to show/ hide Exclyde allocated quantity checkbox
        //It should show only if Fulfillment enabled companies.
        $this->mediateDataAndMetadata_Fulfillment();

        return parent::mediateDataAndMetadata($obj);
    }

    /**
     *
     * @param array $obj
     *
     */
    protected function mediateDataAndMetadata_Header(&$obj)
    {
        $view = $this->getView();

        $view->findAndSetProperty(array('path' => 'WAREHOUSEID'), array('noedit' => true, 'readonly' => true
        , 'noview' => true));

        $view->findAndSetProperty(array('path' => 'EMPUSERID'), array('noedit' => true, 'readonly' => true
        , 'noview' => true));

        $view->findAndSetProperty(array('path' => 'SHOWQTYONHAND'), array('noedit' => true, 'readonly' => true
        , 'noview' => true));

        $view->findAndSetProperty(array('path' => 'EXCLUDEALLOCATEDQTY'), array('noedit' => true, 'readonly' => true
        , 'noview' => true));

        $view->findAndSetProperty(array('path' => 'CYCLECOUNTDESC'), array('noedit' => true, 'readonly' => true
        , 'noview' => true));

        //Auto populate ADJUSTMENTPOSTDATE if it is not set.
        $countStates = [ self::STATE_COUNTED_VALUE, self::STATE_RECONCILED_VALUE, self::STATE_VOIDED_VALUE ];
        if( !$obj['ADJUSTMENTPOSTDATE'] && isset($obj['COUNTSTATE']) && in_array($obj['COUNTSTATE'], $countStates) ) {
            $obj['ADJUSTMENTPOSTDATE'] = GetCurrentDate();
        }
    }

    /**
     * @param array   $obj
     *
     * @throws Exception
     */
    protected function mediateDataAndMetadata_Entries(&$obj)
    {
        $kINVid = &Globals::$g->kINVid;
        GetModulePreferences($kINVid, $invPrefs);
        $gErr = Globals::$g->gErr;

        $view = $this->getView();
        if($obj['COUNTSTATE'] != self::STATE_NOTSTARTED_VALUE){

            if( isset($obj['SHOWQTYONHAND']) && $obj['SHOWQTYONHAND'] == 'true' ){
                $view->findAndSetProperty(array('path' => 'QUANTITYONHAND'),
                                          array(
                                            'hidden' => false,
                                            'fullname' => GT($this->textMap, 'IA.QOH_AS_OF_COUNT_START'),
                                          ));
            }
            $view->findAndSetProperty(array('path' => 'QUANTITYCOUNTED'), array('hidden' => false));
            $view->findAndSetProperty(array('path' => 'QUANTITYDAMAGED'), array('hidden' => false));
            $view->findAndSetProperty(array('path' => 'ADJUSTMENTREASON'), array('hidden' => false));
            $view->findAndSetProperty(array('path' => 'COUNTEDBYID'), array('hidden' => false));
            $view->findAndSetProperty(array('path' => 'LINECOUNTSTATE'), array('hidden' => false));
        } else{
            $view->findAndSetProperty(array('path' => 'QOHLASTUPDATED'), array('hidden' => false));
        }

        $cycleCountItemsSection = array();
        $view->findComponents(array('id' => 'CYCLECOUNT_ITEMS'), EditorComponentFactory::TYPE_SECTION, $cycleCountItemsSection);

        if ( $cycleCountItemsSection[0] ) {
            $cycleCountItemsSection[0]->setProperty('hidden', false);
        }

        if(isset($invPrefs['ENABLEBIN']) && $invPrefs['ENABLEBIN'] == 'T') {
            $view->findAndSetProperty(array('path' => 'BINID'), array('hidden' => false));
            $view->findAndSetProperty(array('path' => 'ICROWID'), array('hidden' => false));
            $view->findAndSetProperty(array('path' => 'AISLEID'), array('hidden' => false));
            $view->findAndSetProperty(array('path' => 'ZONEID'), array('hidden' => false));
        }

        if(isset($invPrefs['ENABLELOT']) && $invPrefs['ENABLELOT'] == 'T') {
            $view->findAndSetProperty(array('path' => 'LOTNO'), array('hidden' => false));
        }

        if(isset($invPrefs['ENABLESERIAL']) && $invPrefs['ENABLESERIAL'] == 'T') {
            $view->findAndSetProperty(array('path' => 'SERIALNO'), array('hidden' => false));
        }

        if(isset($invPrefs['ENABLE_EXPIRATION']) && $invPrefs['ENABLE_EXPIRATION'] == 'T') {
            $view->findAndSetProperty(array('path' => 'EXPIRATIONDATE'), array('hidden' => false));
        }
        //verifying there are skipped item, so that we will show warning message.
        if(Request::$r->_skipcount){
            $fileLine = __FILE__ . ':' . __LINE__;
            $msg1 = GT($this->textMap, 'IA.ONE_OR_MORE_ITEMS_FROM_THIS_COUNT_ARE_SKIPPED');
            $gErr->AddDetailWarning('BL03002185', $fileLine, $msg1);
            $this->warningmessage = true;
            $this->state = $this->kEditWarningState;
        }

        //Setup the href link for clicking on Item Id and Adjustment column links
        $invdocviewop = GetOperationId("inv/lists/invdocument/view");
        $view->findAndSetProperty(array('path' => 'ADJUSTMENT'), array('onclick' => "LaunchObjLink(this, $invdocviewop, 'inv');"));
        $itemviewop = GetOperationId("inv/lists/item/view");
        $view->findAndSetProperty(array('path' => 'ITEMID'), array('onclick' => "LaunchObjLink(this, $itemviewop, 'inv');"));
    }

    /**
     * @param string $state
     *
     * @return array
     */
    public function getStandardButtons($state)
    {
        switch ($state) {
            case Template_CreateWarningState:
            case Editor_ShowNewState:
                $values = $this->createNewStateButtons();
                break;
            case Template_EditWarningState:
            case Editor_ShowEditState:
                $values = $this->createEditStateButtons();
                break;
            case Editor_ShowViewState:
                if ($this->CanShowAuditTrail()) {
                    $this->configureAuditTrailButton($values);
                }

                if($this->CanEdit()) {
                    $this->setButtonDetails($values, 'editbuttid', 'editbutton', 'IA.EDIT', 'edit', false, 'window.editor.doEdit()', false);
                }

                if ($this->CanPrint()) {
                    $url = $this->getCurrentExcelURL();
                    if ( $url !== "" ) {
                        $jsCode = "window.open('$url')";
                        $buttonID = 'IA.EXPORT_WORKSHEET';
                        if(Request::$r->GetCurrentObjectValueByPath('COUNTSTATE') == self::STATE_COUNTED_VALUE){
                            $buttonID = 'IA.EXPORT_COUNT_REPORT';
                        }
                        $this->setButtonDetails(
                            $values, 'saveandexcelbuttid', 'deliverbutton', $buttonID, 'deliver', false, $jsCode, false
                        );
                    }
                }
                $this->setButtonDetails($values, Editor_CancelBtnID, 'cancelbutton', 'IA.DONE', 'cancel', false);
                break;
        }

        $this->addHelpButton($values);
        return $values;
    }


    /**
     * Creates create and cancel buttons for new form state.
     *
     * @return array buttons
     */
    protected function createNewStateButtons()
    {

        if( $this->CanSave() ) {
            $this->setButtonDetails($values, "savecontinue", 'dobutton',"IA.SAVE_AND_CONTINUE", $this->kSaveContinueAction);
        }

        $this->setButtonDetails($values, Editor_CancelBtnID, 'cancelbutton', 'IA.CANCEL', 'cancel', false);
        return $values;
    }

    /**
     * Creates create and cancel buttons for new form state.
     *
     * @return array buttons
     */
    protected function createEditStateButtons()
    {
        $values = array();
        $state = Request::$r->GetCurrentObjectValueByPath('COUNTSTATE');

        if ($this->CanSave()) {
            if($state == self::STATE_NOTSTARTED_VALUE){
                $this->setButtonDetails($values, "updateqoh", 'dobutton', 'IA.UPDATE_QUANTITY_ON_HAND', $this->kUpdateQOHAction);
                $this->setButtonDetails($values, "savestartcount", 'dobutton', 'IA.START_COUNT', $this->kSaveStartCountAction);
            } else if($state == self::STATE_INPROGRESS_VALUE){
                $this->setButtonDetails($values, "savecomplete", 'dobutton', 'IA.COMPLETE_COUNT', $this->kSaveCompleteAction);
            } else if($state == self::STATE_COUNTED_VALUE){
                $this->setButtonDetails($values, "postadjustment", 'dobutton', 'IA.POST_ADJUSTMENT',
                                        $this->kPostAdjustmentAction, false, "beforePostCycleCount()");
                $this->setButtonDetails($values, "voidcount", 'dobutton', 'IA.VOID_COUNT', $this->kVoidCountAction);
            }
        }

        if ($this->CanShowAuditTrail()) {
            $this->configureAuditTrailButton($values);
        }

        if ($this->CanPrint() && $state != self::STATE_COUNTED_VALUE) {
            $url = $this->getCurrentExcelURL();
            if ( $url !== "" ) {
                $jsCode = "window.open('$url')";
                $this->setButtonDetails(
                    $values, 'saveandexcelbuttid', 'deliverbutton', 'IA.PRINT_WORKSHEET', 'deliver', false, $jsCode, false
                );
            }
        }

        $this->setButtonDetails($values, Editor_CancelBtnID, 'cancelbutton', 'IA.DONE', 'cancel', false);

        return $values;
    }

    /**
     * @param array $_params
     * @param array|false $obj
     *
     * @return bool
     */
    function retrieveObjectFromView(&$_params, &$obj)
    {
        $ok = true;
        $ok = $ok && parent::retrieveObjectFromView( $_params, $obj );

        $recordno = Request::$r->_r;

        if(isset($recordno) && $recordno != ''){
            //We are alway getting the stored data because we are using server side pagination and
            // we make sure every data is stored properly in dataabse.
            $storedObjData = $this->entityMgr->get($recordno);
            $obj['CYCLECOUNTENTRY'] = $storedObjData['CYCLECOUNTENTRY'];

            if($obj){

                $ok = $ok && $this->entityMgr->CleanupDerivedFields($obj);
                $this->entityMgr->_ProcessResultForOwnership($obj);

                // this function only validates the dates
                $ok = $ok && $this->PrepareInputValues($_params, $obj);
                Request::$r->SetCurrentObject($obj);
            }
        }

        return $ok;
    }

    /**
     * ProcessSaveContinueAction code for save and continue
     *
     * @param array $_params parameters
     *
     * @return bool true or false
     */
    protected function ProcessSaveContinueAction(&$_params)
    {

        $gErr = Globals::$g->gErr;
        $_params['_iscontinue'] = true;

        $ok = $this->retrieveObjectFromView($_params, $obj);
        $obj = $this->DoRefreshAction($_params, $obj);

        if ( $this->state == $this->kShowNewState ) {
            $ok = $ok && $this->prepareObjectForCreate($obj);
            $ok = $this->innerProcessCreateAction($_params, $obj, $ok);

            $keyFieldName = $this->getEntityMgr()
                ->GetKeyFieldName();

            $_r = empty($obj[$keyFieldName]) ? $obj[':'.$keyFieldName] : $obj[$keyFieldName];

            if ( $ok && ! in_array($this->state, [ $this->kErrorState, $this->kEditWarningState ])
                && ! $gErr->hasWarnings() ) {
                Request::$r->_currentlayer = '';
                Request::$r->_changed = false;

                $this->state = $this->kShowEditState;

                $_sess = Session::getKey();

                $entity = $this->getEntity();
                $application = $this->getEntityMgr()->getWholeSchema()['module'];
                $op = GetOperationId($application . '/lists/' . $entity . '/edit');
                $list_op = GetOperationId($application . '/lists/' . $entity);
                $done = "lister.phtml?.it=$entity&.op=$list_op&.sess=$_sess";
                Fwd('editor.phtml?.sess=' . $_sess . '&.r=' . urlencode($_r) . '&.op=' . $op, $done);
            }
        }

        return $ok;
    }

    /**
     * ProcessStartCountAction
     *
     * @param array $_params parameters
     *
     * @return bool true or false
     */
    protected function ProcessStartCountAction(&$_params)
    {
        return $this->StartCycleCountProcess($_params, true);
    }

    /**
     * ProcessListerStartCountAction
     *
     * @param array $_params parameters
     *
     * @return bool true or false
     */
    protected function ProcessListerStartCountAction(&$_params)
    {
        return $this->StartCycleCountProcess($_params, false);
    }

    /**
     * UpdateQOHAction
     *
     * @param array $_params parameters
     *
     * @return bool true or false
     */
    protected function UpdateQOHAction(&$_params)
    {
        $ok = true;
        $gErr = Globals::$g->gErr;
        $ccMgr = Globals::$g->gManagerFactory->getManager( 'iccyclecount' );

        if ( ! is_object($this->entityMgr) ) {
            $this->entityMgr = $this->GetManager($this->getEntity());
        }

        if ( $this->ProcessErrorRetrivalAction($this->getEntityMgr()) ) {
            $this->state = $this->kShowNewState;

            return true;
        }

        $recordno = Request::$r->_r;
        // Validate if the COUNTSTATE is proper and verif the saved object and from the view.
        // If the state is different thorw error
        if(isset($recordno)){

            $filter = array(
                'selects' => array( 'COUNTSTATE' ),
                'filters' => array(array(array('RECORDNO', '=', $recordno)))
            );
            $countState = $this->entityMgr->GetList($filter);

            if( isset($countState[0]['COUNTSTATE']) && $countState[0]['COUNTSTATE'] == self::STATE_INPROGRESS_VALUE){

                $gErr->addIAError(
                    'INV-0123', __FILE__.":".__LINE__,
                    "Cycle count state is already in progress. Please refresh the screen and try again",
                    []
                );
                $this->state = $this->kErrorState;

                return false;
            }

        }
        $ok = $ok && $this->retrieveObjectFromView($_params, $obj);
        $obj = $this->DoRefreshAction($_params, $obj);

        $currentDate = GetTimestampGMT();
        $obj['QOHLASTUPDATEDDATE'] = $currentDate;

        $ok = $ok && $ccMgr->validateCyclecountEntries($obj);

        $ok = $ok && $ccMgr->populateOnHandQtyOnStartCyclecount($obj);

        $this->entityMgr->setWarningValidation();

        $ok = $ok && $this->entityMgr->set($obj);

        if ($ok) {
            // Clear the warning cache struncture WHEN operation is successful
            Globals::$g->gErr->warningsCache->clear();
        }

        if (!$ok) {
            $obj['QOHLASTUPDATEDDATE'] = '';
            $entityDesc = $_params['entity'];

            if (Globals::$g->gErr->hasWarnings()) {
                $this->warningmessage = true;
                $this->state = $this->kEditWarningState;
            }

            if ($gErr->hasErrors()) {
                $gErr->addIAError('INV-0528', __FILE__.":".__LINE__,
                "Update $entityDesc failed",
                ['ENTITY_DESC'=>$entityDesc]);
                $this->state = $this->kErrorState;
            }
        }

        if ($ok) {
            Request::$r->_changed = false;
            $_sess = Session::getKey();
            $entity = $this->getEntity();
            $application = $this->getEntityMgr()->getWholeSchema()['module'];

            $op = GetOperationId($application . '/lists/' . $entity. '/edit');
            $done = "lister.phtml?.it=$entity&.op=$op&.sess=$_sess";
            Fwd('editor.phtml?.sess=' . $_sess . '&.r=' . urlencode($recordno) . '&.op=' . $op, $done);
        }

        return $ok;
    }

    /**
     * StartCycleCountProcess code for Start the Cycle Count
     *
     * @param array $_params parameters
     * @param bool $fromEditor parameters
     *
     * @return bool true or false
     */
    protected function StartCycleCountProcess(&$_params, $fromEditor = true)
    {
        $ok = true;
        $gErr = Globals::$g->gErr;
        $skipCountEntries = false;
        $ccMgr = Globals::$g->gManagerFactory->getManager( 'iccyclecount' );

        if ( ! is_object($this->entityMgr) ) {
            $this->entityMgr = $this->GetManager($this->getEntity());
        }

        if ( $this->ProcessErrorRetrivalAction($this->getEntityMgr()) ) {
            $this->state = $this->kShowNewState;

            return true;
        }

        $recordno = Request::$r->_r;

        // Validate if the COUNTSTATE is proper and verif the saved object and from the view.
        // If the state is different thorw error
        if(isset($recordno)){

            $filter = array(
                'selects' => array( 'COUNTSTATE' ),
                'filters' => array(array(array('RECORDNO', '=', $recordno)))
            );
            $countState = $this->entityMgr->GetList($filter);

            if( isset($countState[0]['COUNTSTATE']) && $countState[0]['COUNTSTATE'] == self::STATE_INPROGRESS_VALUE){

                $gErr->addIAError(
                    'INV-0124', __FILE__.":".__LINE__,
                    "Cycle count state is already in progress. Please refresh the screen and try again",
                    []
                );
                $this->state = $this->kErrorState;

                return false;
            }

        }

        if($fromEditor){
            $ok = $ok && $this->retrieveObjectFromView($_params, $obj);
            $obj = $this->DoRefreshAction($_params, $obj);
        } else {
            $obj = $this->entityMgr->get($recordno);
        }

        $currentDate = GetTimestampGMT();
        $oldCountState = $obj['COUNTSTATE'];
        $obj['COUNTSTATE'] = self::STATE_INPROGRESS_VALUE;
        $obj['COUNTSTARTDATE'] = $currentDate;

        $ok = $ok && $ccMgr->validateCyclecountEntries($obj);

        $ok = $ok && $ccMgr->populateOnHandQtyOnStartCyclecount($obj);

        if($ok){
            $skipCountEntries = $ccMgr->getSkipCycleCountList($obj['CYCLECOUNTENTRY'], $obj['WAREHOUSEID']);
        }

        //populate lines in count here on start count
        $obj['LINESINCOUNT'] = Util::countOrZero($obj['CYCLECOUNTENTRY']);

        $this->entityMgr->setWarningValidation();

        $ok = $ok && $this->entityMgr->set($obj);

        if ($ok) {
            // Clear the warning cache struncture WHEN operation is successful
            Globals::$g->gErr->warningsCache->clear();
        }

        if (!$ok) {
            $obj['COUNTSTATE'] = $oldCountState;
            $obj['COUNTSTARTDATE'] = '';
            $entityDesc = $_params['entity'];

            if (Globals::$g->gErr->hasWarnings()) {
                $this->warningmessage = true;
                $this->state = $this->kEditWarningState;
            }

            if ($gErr->hasErrors()) {
                $gErr->addIAError('INV-0673', __FILE__.":".__LINE__,
                "Update $entityDesc failed",['ENTITY_DESC'=>$entityDesc]);
                $this->state = $this->kErrorState;
            }
        }

        if ($ok) {
            Request::$r->_changed = false;
            $_sess = Session::getKey();
            $entity = $this->getEntity();
            $application = $this->getEntityMgr()->getWholeSchema()['module'];

            $op = GetOperationId($application . '/lists/' . $entity. '/edit');
            $done = "lister.phtml?.it=$entity&.op=$op&.sess=$_sess";
            Fwd('editor.phtml?.sess=' . $_sess . '&.r=' . urlencode($recordno) . '&.op=' . $op . '&.skipcount='. $skipCountEntries, $done);
        }

        return $ok;
    }

    /**
     * ProcessCompleteAction code for completing the cycle count
     *
     * @param array $_params parameters
     *
     * @return bool true or false
     */
    protected function ProcessCompleteAction(&$_params)
    {

        $gErr = Globals::$g->gErr;
        $ccMgr = Globals::$g->gManagerFactory->getManager( 'iccyclecount' );

        if ( ! is_object($this->entityMgr) ) {
            $this->entityMgr = $this->GetManager($this->getEntity());
        }

        if ( $this->ProcessErrorRetrivalAction($this->getEntityMgr()) ) {
            $this->state = $this->kShowNewState;

            return true;
        }

        $recordno = Request::$r->_r;

        // Validate if the COUNTSTATE is proper and verif the saved object and from the view.
        // If the state is different thorw error
        if(isset($recordno)){

            $filter = array(
                'selects' => array( 'COUNTSTATE' ),
                'filters' => array(array(array('RECORDNO', '=', $recordno)))
            );
            $countState = $this->entityMgr->GetList($filter);

            if( isset($countState[0]['COUNTSTATE']) && $countState[0]['COUNTSTATE'] == self::STATE_COUNTED_VALUE){

                $gErr->addIAError(
                    'INV-0125', __FILE__.":".__LINE__,
                    "Cycle count state is already completed. Please refresh the screen and try again",
                    []
                );
                $this->state = $this->kErrorState;

                return false;
            }

        }

        $ok = $this->retrieveObjectFromView($_params, $obj);
        $obj = $this->DoRefreshAction($_params, $obj);

        $currentDate = GetTimestampGMT();
        $oldCountState = $obj['COUNTSTATE'];
        $obj['COUNTSTATE'] = self::STATE_COUNTED_VALUE;
        $obj['COUNTENDDATE'] = $currentDate;

        $ok = $ok && $ccMgr->validateCyclecountEntries($obj);

        $this->entityMgr->setWarningValidation();

        $ok = $ok && $this->entityMgr->set($obj);

        if ($ok) {
            // Clear the warning cache struncture WHEN operation is successful
            Globals::$g->gErr->warningsCache->clear();
        }

        if (!$ok) {
            $obj['COUNTSTATE'] = $oldCountState;
            $obj['COUNTENDDATE'] = '';
            $entityDesc = $_params['entity'];
            if (Globals::$g->gErr->hasWarnings()) {
                $this->warningmessage = true;
                $this->state = $this->kEditWarningState;
            }

            if ($gErr->hasErrors()) {
                $gErr->addIAError('INV-0529', __FILE__.":".__LINE__,
                "Completing $entityDesc failed",['ENTITY_DESC'=>$entityDesc]);
                $this->state = $this->kErrorState;
            }
        }

        if ( $ok && ! in_array($this->state, [ $this->kErrorState, $this->kEditWarningState ])
            && ! $gErr->hasWarnings() ) {

            Request::$r->_changed = false;
            $_sess = Session::getKey();
            $entity = $this->getEntity();

            $application = $this->getEntityMgr()->getWholeSchema()['module'];
            $op = GetOperationId($application . '/lists/' . $entity);

            $done = "lister.phtml?.it=$entity&.op=$op&.sess=$_sess";

            Redirect($done);
        }

        return $ok;
    }

    /**
     * ProcessSaveandNew code for save and new
     *
     * @param array $_params parameters
     *
     * @return bool true or false
     */
    protected function ProcessSaveandNew(&$_params)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;

        if ( ! is_object($this->entityMgr) ) {
            $this->entityMgr = $this->GetManager($this->getEntity());
        }

        if ( $this->ProcessErrorRetrivalAction($this->getEntityMgr()) ) {
            $this->state = $this->kShowNewState;

            return true;
        }

        $ok = $ok && $this->retrieveObjectFromView($_params, $obj);
        $obj = $this->DoRefreshAction($_params, $obj);
        $ok = $ok && $this->prepareObjectForSave($obj);
        $ok = $ok && $this->innerProcessSaveAction($_params, $obj, $ok);

        if (!$ok) {
            $entityDesc = $_params['entity'];
            if (Globals::$g->gErr->hasWarnings()) {
                $this->warningmessage = true;
                $this->state = $this->kEditWarningState;
            }

            if ($gErr->hasErrors()) {
                $gErr->addIAError('INV-0530', __FILE__.":".__LINE__,
                "Creating $entityDesc failed",['ENTITY_DESC'=>$entityDesc]);
                $this->state = $this->kErrorState;
            }
        }

        if ( $ok && ! in_array($this->state, [ $this->kErrorState, $this->kEditWarningState ])
            && ! $gErr->hasWarnings() ) {

            Request::$r->_changed = false;
            $_sess = Session::getKey();
            $entity = $this->getEntity();
            $application = $this->getEntityMgr()->getWholeSchema()['module'];
            $op = GetOperationId($application . '/lists/' . $entity . '/create');

            $done = "lister.phtml?.it=$entity&.op=$op&.sess=$_sess";
            Fwd('editor.phtml?.sess=' . $_sess .'&.op=' . $op.'&.ifmod=inv', $done);
        }

        return $ok;
    }


    /**
     * VoidCountAction code for completing the cycle count
     *
     * @param array $_params parameters
     *
     * @return bool true or false
     */
    protected function PostAdjustmentAction(&$_params)
    {

        $gErr = Globals::$g->gErr;
        $ok = true;
        $ccMgr = Globals::$g->gManagerFactory->getManager( 'iccyclecount' );

        if ( ! is_object($this->entityMgr) ) {
            $this->entityMgr = $this->GetManager($this->getEntity());
        }

        if ( $this->ProcessErrorRetrivalAction($this->getEntityMgr()) ) {
            $this->state = $this->kShowNewState;
            return true;
        }

        $recordno = Request::$r->_r;

        // Validate if the COUNTSTATE is proper and verif the saved object and from the view.
        // If the state is different thorw error
        if(isset($recordno)){

            $filter = array(
                'selects' => array( 'COUNTSTATE' ),
                'filters' => array(array(array('RECORDNO', '=', $recordno)))
            );
            $countState = $this->entityMgr->GetList($filter);

            if( isset($countState[0]['COUNTSTATE']) && $countState[0]['COUNTSTATE'] == self::STATE_RECONCILED_VALUE){

                $gErr->addIAError('INV-0126', __FILE__.":".__LINE__,
                    "Cycle count state is already reconciled. Please refresh the screen and try again",
                    []
                );
                $this->state = $this->kErrorState;

                return false;
            }

        }

        $ok = $ok && $this->retrieveObjectFromView($_params, $obj);
        $obj = $this->DoRefreshAction($_params, $obj);

        //prepare Dimesnsion for entries
        $ok = $ok && $this->populateDimValuesForEntries($_params, $obj);

        $mappingEntries = [];
        $ok = $ok && $ccMgr->postAdjustments($obj, $mappingEntries);
        if($ok){
            $ccMgr->prepareDocumentLinksForCC($obj, $mappingEntries);
            $ccMgr->rePopulateUnitCostOnReconcile($obj);
        }

        if($ok){
            $currentDate = GetTimestampGMT();
            $obj['COUNTSTATE'] = self::STATE_RECONCILED_VALUE;
            $obj['ADJUSTMENTDATE'] = $currentDate;
        }

        $this->entityMgr->setWarningValidation();

        $ok = $ok && $this->entityMgr->set($obj);
        if ($ok) {
            // Clear the warning cache struncture WHEN operation is successful
            Globals::$g->gErr->warningsCache->clear();
        }

        if (!$ok) {
            global $gGoBackParams;
            $gGoBackParams['_reconcile'] = 'true';
            $entityDesc = $_params['entity'];
            Request::$r->_changed = false;
            if (Globals::$g->gErr->hasWarnings()) {
                $this->warningmessage = true;
                $this->state = $this->kEditWarningState;
            }

            if ($gErr->hasErrors()) {
                $gErr->addIAError('INV-0674', __FILE__.":".__LINE__,
                "Completing $entityDesc failed",['ENTITY_DESC'=>$entityDesc]);
                $this->state = $this->kErrorState;
            }
        }

        if ( $ok && ! in_array($this->state, [ $this->kErrorState, $this->kEditWarningState ])
            && ! $gErr->hasWarnings() ) {

            Request::$r->_changed = false;
            $_sess = Session::getKey();
            $entity = $this->getEntity();

            $application = $this->getEntityMgr()->getWholeSchema()['module'];
            $op = GetOperationId($application . '/lists/' . $entity);

            $done = "lister.phtml?.it=$entity&.op=$op&.sess=$_sess";

            Redirect($done);
        }

        return $ok;
    }

    /**
     * VoidCountAction code for completing the cycle count
     *
     * @param array $_params parameters
     *
     * @return bool true or false
     */
    protected function VoidCountAction(&$_params)
    {

        $gErr = Globals::$g->gErr;
        $ok = true;

        if ( ! is_object($this->entityMgr) ) {
            $this->entityMgr = $this->GetManager($this->getEntity());
        }

        if ( $this->ProcessErrorRetrivalAction($this->getEntityMgr()) ) {
            $this->state = $this->kShowNewState;
            return true;
        }

        $recordno = Request::$r->_r;

        // Validate if the COUNTSTATE is proper and verif the saved object and from the view.
        // If the state is different thorw error
        if(isset($recordno)){

        $filter = array(
            'selects' => array( 'COUNTSTATE' ),
            'filters' => array(array(array('RECORDNO', '=', $recordno)))
        );
        $countState = $this->entityMgr->GetList($filter);

        if( isset($countState[0]['COUNTSTATE']) && $countState[0]['COUNTSTATE'] == self::STATE_VOIDED_VALUE){

            $gErr->addIAError('INV-0127', __FILE__.":".__LINE__,
                "Cycle count state is already voided. Please refresh the screen and try again",
                []
            );
            $this->state = $this->kErrorState;

            return false;
        }

    }

        $ok = $ok && $this->retrieveObjectFromView($_params, $obj);
        $obj = $this->DoRefreshAction($_params, $obj);
        $reconcileFields = ['ACTUALADJ', 'ACTUALDMGADJ', 'ADJVALUE'];

        foreach ($obj['CYCLECOUNTENTRY'] as &$cycleCountEntry ){
            foreach ($reconcileFields as &$field ){
                unset($cycleCountEntry[$field]);
            }
        }

        if($ok){
            $obj['COUNTSTATE'] = self::STATE_VOIDED_VALUE;
            $obj['ADJUSTMENTCOUNT'] = 0;
            $obj['DMGADJUSTMENTCOUNT'] = 0;
        }

        $this->entityMgr->setWarningValidation();

        $ok = $ok && $this->entityMgr->set($obj);
        if ($ok) {
            // Clear the warning cache struncture WHEN operation is successful
            Globals::$g->gErr->warningsCache->clear();
        }

        if (!$ok) {
            global $gGoBackParams;
            $gGoBackParams['_reconcile'] = 'true';
            $entityDesc = $_params['entity'];
            if (Globals::$g->gErr->hasWarnings()) {
                $this->warningmessage = true;
                $this->state = $this->kEditWarningState;
            }

            if ($gErr->hasErrors()) {
                $gErr->addIAError('INV-0675', __FILE__.":".__LINE__,
                "Completing $entityDesc failed",['ENTITY_DESC'=>$entityDesc]);
                $this->state = $this->kErrorState;
            }
        }

        if ( $ok && ! in_array($this->state, [ $this->kErrorState, $this->kEditWarningState ])
            && ! $gErr->hasWarnings() ) {

            Request::$r->_changed = false;
            $_sess = Session::getKey();
            $entity = $this->getEntity();

            $application = $this->getEntityMgr()->getWholeSchema()['module'];
            $op = GetOperationId($application . '/lists/' . $entity);

            $done = "lister.phtml?.it=$entity&.op=$op&.sess=$_sess";

            Redirect($done);
        }

        return $ok;
    }

    /**
     * Returns the reconciliation request.
     *
     * @return array
     */
    protected function getCycleCountRequestParams()
    {
        $request = [];

        //Cyclecount RecordNo
        $request['CYCLECOUNTKEY'] = Request::$r->{'_r'};

        // Add the additional UI information
        $request['QUERYID'] = Request::$r->{'_queryid'};
        $request['PAGE'] = Request::$r->{'_page'};
        $request['PAGESIZE'] = Request::$r->{'_pagesize'};

        // Common Grid Search filters both CYCLECOUNTENTRY and CYCLECOUNTRECORD
        $request['ITEMID'] = Request::$r->{'_itemid'};
        $request['ITEMNAME'] = Request::$r->{'_itemname'};
        $request['BINID']  = Request::$r->{'_binid'};
        $request['ICROWID'] = Request::$r->{'_icrowid'};
        $request['AISLEID'] = Request::$r->{'_aisleid'};
        $request['ZONEID']  = Request::$r->{'_zoneid'};
        $request['SERIALNO'] = Request::$r->{'_serialno'};
        $request['LOTNO'] = Request::$r->{'_lotno'};
        $request['ITEMUNIT'] = Request::$r->{'_itemunit'};

        // Specific Grid Search filters for CYCLECOUNTENTRY
        $request['QUANTITYCOUNTED'] = Request::$r->{'_quantitycounted'};
        $request['QUANTITYDAMAGED'] = Request::$r->{'_quantitydamaged'};
        $request['QUANTITYONHAND'] = Request::$r->{'_quantityonhand'};
        $request['ADJUSTMENTREASON'] = Request::$r->{'_adjustmentreason'};
        $request['LINECOUNTSTATE'] = Request::$r->{'_linecountstate'};
        $request['COUNTEDBYID']  = Request::$r->{'_countedbyid'};
        $request['TOTALQTYCOUNTED']  = Request::$r->{'_totalqtycounted'};
        $request['SUGGESTEDADJ']  = Request::$r->{'_suggestedadj'};
        $request['SUGGESTEDDMGADJ']  = Request::$r->{'_suggesteddmgadj'};
        $request['ACTUALADJ']  = Request::$r->{'_actualadj'};
        $request['ACTUALDMGADJ']  = Request::$r->{'_actualdmgadj'};
        $request['UNITCOST']  = Request::$r->{'_unitcost'};
        $request['ADJVALUE']  = Request::$r->{'_adjvalue'};
        $request['REVIEWCOMMENT']  = Request::$r->{'_reviewcomment'};
        $request['QUANTITYONHANDEND']  = Request::$r->{'_quantityonhandend'};

        // Specific Grid Search filters for CYCLECOUNTRECORD
        $request['ITEMCYCLE'] = Request::$r->{'_itemcycle'};
        $request['PRODUCTLINE'] = Request::$r->{'_productline'};

        //Common field WAREHOUSEKEY for getCycleCountData and insertCycleCountEntries
        $request['WAREHOUSEKEY'] = Request::$r->{'_warehousedata'};

        // Specific request fields for insertCycleCountEntries, skipCycleCountEntries and removeCycleCountEntries
        $request['ADDCOUNTEDBYID']  = Request::$r->{'_addcountedbyid'};
        //Selection state parameter
        //State of selection ALL or ALL_EXCEPT_SOME or NONE_EXCEPT_SOME
        $request['SELECTIONSTATE']   = Request::$r->{'_selectionstate'};
        $request['EXCEPTIONENTRIES'] = Request::$r->{'_exceptionentries'};


        // Order fields for both Grid
        $request['ORDERS'] = Request::$r->{'orders'};


        //Specific request fields for updateCycleCountEntries
        $request['ENTRYRECORDNO']   = Request::$r->{'_entryrecordno'};
        $request['FIELDCHANGED'] = Request::$r->{'_fieldchanged'};

        //For fields QUANTITYCOUNTED and QUANTITYDAMAGED
        $request['UPDATESTATE']     = Request::$r->{'_updatestate'};
        $request['UPDATEQTYCOUNTED'] = Request::$r->{'_updateqtycounted'};
        $request['UPDATEQTYDAMAGED'] = Request::$r->{'_updateqtydamaged'};


        //For fields ADJUSTMENTREASON
        $request['UPDATEADJREASON'] = Request::$r->{'_updateadjreason'};


        //For fields COUNTEDBYID and COUNTEDBYKEY
        $request['UPDATECNTBYID']  = Request::$r->{'_updatecntbyid'};

        //additionalCycleCountEntry parameters
        $request['ADDITEMID']   = Request::$r->{'_additemid'};
        $request['ADDBINID']    = Request::$r->{'_addbinid'};
        $request['ADDSERIALNO'] = Request::$r->{'_addserialno'};
        $request['ADDLOTNO']    = Request::$r->{'_addlotno'};
        $request['ADDEXPIRATIONDATE']    = Request::$r->{'_addexpirationdate'};

        //adding Reconciling parameters
        $request['UPDATERECONCILEQTY']  = Request::$r->{'_updatereconcileqty'} == "" ? 0:  Request::$r->{'_updatereconcileqty'};
        $request['UPDATERECONCILECOST'] = Request::$r->{'_updatereconcilecost'};
        $request['UPDATEREVIEWCOMMENT'] = Request::$r->{'_updatereviewcomment'};
        $request['COSTMETHOD']          = Request::$r->{'_costmethod'};

        //Added for update qty
        $request['QOHLASTUPDATED']  = Request::$r->{'_qohlastupdated'};

        //EXCLUDEALLOCATEDQTY field to exlude allocated from the QOH if check box is checked
        $request['EXCLUDEALLOCATEDQTY'] = Request::$r->{'_excludeallocatedqty'};

        return $request;
    }

    /**
     * loadCycleCountData add the selected cycle count entries
     *
     * @param array $requestParams
     *
     * @return array $addedRows  the rows added in JSON format so that they can be added to the entry grid
     */
    protected function loadCycleCountData($requestParams)
    {
        $queryId  = $requestParams['QUERYID'];
        $page     = $requestParams['PAGE'];
        $pageSize = $requestParams['PAGESIZE'];
        $orders   = $requestParams['ORDERS'];
        $cycleCountRecordNo = Request::$r->{'_r'};
        $params   = [];

        if(!isset($requestParams['CYCLECOUNTKEY']) || $requestParams['CYCLECOUNTKEY'] == '') {
            $requestParams['CYCLECOUNTKEY'] = $cycleCountRecordNo;
        }

        $ccMgr = Globals::$g->gManagerFactory->getManager( 'iccyclecount' );

        $cycleCountEntryMgr = $this->GetManager('iccyclecountentry');

        $filterArray = $ccMgr->getFilters($requestParams, false);

        if( is_array($filterArray) && count($filterArray) > 0){
            // Get the query filters
            $params = [
                'filters' => [$filterArray],
            ];
        }

        if ( $page !== -1 && $pageSize !== -1) {
            $params['start'] = $page * $pageSize;
            $params['max'] = $pageSize;
        }

        // Add the orders if any, by default we sort by ITEMID in asc
        $params['orders'] = [ [ 'ITEMID', 'asc' ] ];
        if (!empty($orders)) {
            $params['orders'] = [$orders];
        }

        $params['isCaseInsensitive'] = true;

        $cycleCountData = $cycleCountEntryMgr->GetList($params, false, false);

        $numRecords = 0;
        if (count($cycleCountData)) {
            $numRecords = $cycleCountData[0]['QCNT'];
        }

        return ['PARAMS' => ['QUERYID' => $queryId, 'TOTAL_RECORDS' => $numRecords, 'PAGE' => $page,
            'PAGE_SIZE' => $pageSize], 'RESULT_SET' => $cycleCountData];
    }

    /**
     * getCycleCountData add the selected cycle count entries
     *
     * @param array $requestParams
     *
     * @return array|bool $addedRows  the rows added in JSON format so that they can be added to the entry grid or return false in case of error
     */
    protected function getCycleCountData($requestParams)
    {
        $cycleCountData = [];
        $numRecords = 0;

        $warehouseKey = $requestParams['WAREHOUSEKEY'];
        $queryId      = $requestParams['QUERYID'];
        $page         = $requestParams['PAGE'];
        $pageSize     = $requestParams['PAGESIZE'];

        //Set a filter to excludeOnQOH
        $requestParams['EXCLUDE_ZERO_QOH'] = true;

        //Get the physical Inventory data to process Cycle Count
        if(isset($warehouseKey) && $warehouseKey != ''){
            $ccMgr = Globals::$g->gManagerFactory->getManager( 'iccyclecount' );
            $cycleCountData = $ccMgr->executeCycleCountQuery($warehouseKey, true, false, $requestParams);
        }

        if (is_array($cycleCountData) && count($cycleCountData)) {
            $numRecords = $cycleCountData[0]['QCNT'];
        } else if (!is_array($cycleCountData) && $cycleCountData === false) {
            // return false in case of query error
            return false;
        }

        return ['PARAMS' => ['QUERYID' => $queryId, 'TOTAL_RECORDS' => $numRecords, 'PAGE' => $page,
            'PAGE_SIZE' => $pageSize], 'RESULT_SET' => $cycleCountData];
    }

    /**
     * insertCycleCountEntries add the selected cycle count entries
     * @param array $requestParams
     *
     * @return array
     */
    protected function insertCycleCountEntries($requestParams)
    {
        $ok = true;
        $data = [];
        $addedCycleCountData = [];
        $skipCountEntries = false;
        $countedbyId         = $requestParams['ADDCOUNTEDBYID'];
        $warehouseKey        = $requestParams['WAREHOUSEKEY'];
        $cycleCountRecordNo  = $requestParams['CYCLECOUNTKEY'];
        $ccMgr = Globals::$g->gManagerFactory->getManager( 'iccyclecount' );

        if ( ! is_object($this->entityMgr) ) {
            $this->entityMgr = $this->GetManager($this->getEntity());
        }

        //State of selection ALL or ALL_EXCEPT_SOME or NONE_EXCEPT_SOME
        $selectionState = $requestParams['SELECTIONSTATE'];

        //Set a filter to exclude Zero QOH items
        $requestParams['EXCLUDE_ZERO_QOH'] = true;

        //ExceptionEntries are the entries based on the SELECT type.
        // If the state is ALL, then it will be empty means delete all entries.
        // If the state is ALL_EXCEPT_SOME, then we should delete all other entries except which are in the exceptionEntries.
        // If the state is NONE_EXCEPT_SOME, then delete all entries which are in the exceptionEntries.
        $exceptionEntries = $requestParams['EXCEPTIONENTRIES'];

        if (isset($selectionState) && isset($warehouseKey) && $warehouseKey != '') {

            if ($selectionState === self::ALL || $selectionState === self::ALL_EXCEPT_SOME) {

                if ($selectionState === self::ALL_EXCEPT_SOME && is_array($exceptionEntries)
                    && count($exceptionEntries) > 0) {
                    $requestParams['UNIQUEKEYS'] = $exceptionEntries;
                }

            } else if ($selectionState === self::NONE_EXCEPT_SOME && is_array($exceptionEntries)
                && count($exceptionEntries) > 0) {

                $requestParams['UNIQUEKEYS'] = $exceptionEntries;

            }

            //Get the physical Inventory data to add it to main grid
            $addedCycleCountData = $ccMgr->executeCycleCountQuery($warehouseKey, false, true, $requestParams);
            if (!is_array($addedCycleCountData) && $addedCycleCountData === false) {
                // return false in case of query error
                $ok = false;
            }
        }
        // adding this check to avoid executing the get function case of executeCycleCountQuery query error
        if ($ok) {
            $obj = $this->entityMgr->get($cycleCountRecordNo);

            // added this check to verify if $addedCycleCountData is array or false only in case of query error
            if (isset($obj['COUNTSTATE']) && $obj['COUNTSTATE'] == self::STATE_INPROGRESS_VALUE && is_array($addedCycleCountData)) {
                $skipCountEntries = $ccMgr->getSkipCycleCountList($addedCycleCountData, $warehouseKey);
            }

            $obj['CYCLECOUNTENTRY'] =is_array($obj['CYCLECOUNTENTRY']) ? $obj['CYCLECOUNTENTRY'] : [];
            if (is_array($addedCycleCountData) && count($addedCycleCountData) > 0) {
                //populate default data so that it can be used for filtering
                foreach ($addedCycleCountData as $key => $selectedRow) {
                    if ($addedCycleCountData[$key]['LINECOUNTSTATE'] !== 'Skipped') {
                        $addedCycleCountData[$key]['COUNTEDBYID'] = $countedbyId;
                        $addedCycleCountData[$key]['LINECOUNTSTATE'] = 'Not Counted';
                    }
                    unset($addedCycleCountData[$key]['QCNT']);
                    $duplicate= false;
                    foreach($obj['CYCLECOUNTENTRY'] as $ccEntry) {
                       if($ccEntry['UNIQUEPROPONROW']===$addedCycleCountData[$key]['UNIQUEPROPONROW']){
                           $duplicate=true;
                           break;
                       }
                    }
                    if(!$duplicate) {
                        $obj['CYCLECOUNTENTRY'][] = $addedCycleCountData[$key];
                    }
                }

                $obj['LINESINCOUNT'] = Util::countOrZero($obj['CYCLECOUNTENTRY']);
                $ok = $ok && $this->entityMgr->set($obj);
            }
        }

        $data[] = $ok;

        if($skipCountEntries){
            $data[] = 'skipped';
        }


        return $data;
    }

    /**
     * updateCycleCountEntries add the selected cycle count entries
     *
     * @param array $requestParams
     *
     * @return array
     */
    protected function updateCycleCountEntries($requestParams)
    {
        $ok = true;
        $data = [];
        $count = '';
        $headerAdjCalculated = false;
        $cycleCountRecordNo = $requestParams['CYCLECOUNTKEY'];
        $ccEntryRecordNo    = $requestParams['ENTRYRECORDNO'];
        $fieldChanged       = $requestParams['FIELDCHANGED'];

        if($fieldChanged == 'QUANTITYCOUNTED' || $fieldChanged == 'QUANTITYDAMAGED'){

            $lineCountState  = $requestParams['UPDATESTATE'];
            $quantityCounted = $requestParams['UPDATEQTYCOUNTED'];
            $quantityDamaged = $requestParams['UPDATEQTYDAMAGED'];


            $qry = "UPDATE iccyclecountentry SET linecountstate  = :1, quantitycounted = :2, quantitydamaged = :3 WHERE
                    cyclecountkey = :4  AND record# = :5  AND cny# = :6";
            $ok = $ok && ExecStmt([ $qry, $lineCountState, $quantityCounted, $quantityDamaged,
                    $cycleCountRecordNo, $ccEntryRecordNo, GetMyCompany() ]);

        } elseif ($fieldChanged == 'ADJUSTMENTREASON'){

            $adjustmentReson = $requestParams['UPDATEADJREASON'];
            $qry = "UPDATE iccyclecountentry SET adjustmentreason  = :1 WHERE cyclecountkey = :2 AND record# = :3 
                    AND cny# = :4";
            $ok = $ok && ExecStmt([ $qry, $adjustmentReson, $cycleCountRecordNo, $ccEntryRecordNo, GetMyCompany() ]);

        } elseif ($fieldChanged == 'COUNTEDBYID') {
            if(isset($requestParams['UPDATECNTBYID']) && $requestParams['UPDATECNTBYID'] != ''){
                $countedById = explode('--', $requestParams['UPDATECNTBYID'])[0];
                $countedByKey = '';
                $employeeMgr  = Globals::$g->gManagerFactory->getManager('employee');
                $filter = array(
                    'selects' => array('RECORDNO'),
                    'filters' => array(
                        array(
                            array('EMPLOYEEID', '=', $countedById),
                        )
                    ),
                );
                $res = $employeeMgr->GetList($filter);
                if ($res[0]['RECORDNO']) {
                    $countedByKey = $res[0]['RECORDNO'];
                } else {
                    $ok = false ;
                }

                $qry = "UPDATE iccyclecountentry SET countedbykey  = :1 WHERE cyclecountkey = :2 AND record# = :3 
                    AND cny# = :4";
                $ok = $ok && ExecStmt([ $qry, $countedByKey, $cycleCountRecordNo, $ccEntryRecordNo, GetMyCompany() ]);
            }

        } else if($fieldChanged == 'ACTUALADJ' || $fieldChanged == 'ACTUALDMGADJ'){
            $reconcileQuantity = $requestParams['UPDATERECONCILEQTY'];
            $costMethod = $requestParams['COSTMETHOD'];

            if($fieldChanged == 'ACTUALADJ'){
                $updateCost = ', adjvalue = (unitcost * :1)';
            } else {
                $updateCost = '';
            }

            if( ($costMethod === 'F' || $costMethod === 'L')  && $reconcileQuantity < 0){
                $updateCost = ', unitcost = 0, adjvalue = 0';
            }

            $headerAdjCalculated = true;

            $qry = "UPDATE iccyclecountentry SET $fieldChanged = :1$updateCost WHERE cyclecountkey = :2  AND record# = :3 
                    AND cny# = :4";
            $ok = $ok && ExecStmt([ $qry, $reconcileQuantity, $cycleCountRecordNo, $ccEntryRecordNo, GetMyCompany() ]);


            $qry = "SELECT count(1) as total from iccyclecountentry  WHERE cyclecountkey = :1 AND cny# = :3 and $fieldChanged != 0";
            $res = QueryResult([ $qry, $cycleCountRecordNo, $ccEntryRecordNo, GetMyCompany() ]);

            $count = $res[0]['TOTAL'];
            if($fieldChanged == 'ACTUALADJ'){
                $qry = "UPDATE iccyclecount SET adjustmentcount = :1 WHERE record# = :2  AND cny# = :3";
                $ok = $ok && ExecStmt([ $qry, $count, $cycleCountRecordNo, GetMyCompany() ]);

            } else {
                $qry = "UPDATE iccyclecount SET dmgadjustmentcount = :1 WHERE record# = :2  AND cny# = :3";
                $ok = $ok && ExecStmt([ $qry, $count, $cycleCountRecordNo, GetMyCompany() ]);
            }

        } else if($fieldChanged == 'UNITCOST'){
            $reconcileCost = $requestParams['UPDATERECONCILECOST'];

            $qry = "UPDATE iccyclecountentry SET $fieldChanged = :1, adjvalue = (:1 * actualadj) 
                    WHERE cyclecountkey = :2  AND record# = :3  AND cny# = :4";
            $ok = $ok && ExecStmt([ $qry, $reconcileCost, $cycleCountRecordNo, $ccEntryRecordNo, GetMyCompany() ]);

        } else if($fieldChanged == 'REVIEWCOMMENT'){
            $reviewComment = $requestParams['UPDATEREVIEWCOMMENT'];

            $qry = "UPDATE iccyclecountentry SET $fieldChanged = :1 WHERE cyclecountkey = :2  AND record# = :3 
                    AND cny# = :4";
            $ok = $ok && ExecStmt([ $qry, $reviewComment, $cycleCountRecordNo, $ccEntryRecordNo, GetMyCompany() ]);

        }
        $data[] = $ok;

        if($headerAdjCalculated){
            $data[] = $count;
        }
        return $data;
    }

    /**
     * skipCycleCountEntries skip the selected cycle count entries
     * @param array $requestParams
     *
     *
     * @return bool
     */
    protected function skipCycleCountEntries($requestParams)
    {
        $ok = true;
        $skipRecordNo = [];
        $cycleCountRecordNo = $requestParams['CYCLECOUNTKEY'];
        $ccMgr = Globals::$g->gManagerFactory->getManager( 'iccyclecount' );

        //State of selection ALL or ALL_EXCEPT_SOME or NONE_EXCEPT_SOME
        $selectionState = $requestParams['SELECTIONSTATE'];

        //ExceptionEntries are the entries based on the SELECT type.
        // If the state is ALL, then it will be empty means delete all entries.
        // If the state is ALL_EXCEPT_SOME, then we should delete all other entries except which are in the exceptionEntries.
        // If the state is NONE_EXCEPT_SOME, then delete all entries which are in the exceptionEntries.
        $exceptionEntries = $requestParams['EXCEPTIONENTRIES'];

        if(isset($selectionState)){
            $ccEntryManager = $this->GetManager('iccyclecountentry');
            if($selectionState === self::ALL || $selectionState === self::ALL_EXCEPT_SOME){
                $filters = [];

                $filterArray = $ccMgr->getFilters($requestParams, false);
                if( is_array($filterArray) && count($filterArray) > 0){
                    // Get the fields filters for the seletion State All and feild filter selected.
                    //or else it will delete the other records which it should not delete. Avoiding it by adding
                    // Fields filters.
                    $filters = $filterArray;
                }
                if($selectionState === self::ALL_EXCEPT_SOME && is_array($exceptionEntries)
                    && count($exceptionEntries) > 0 ){
                    $filters[] = [ 'RECORDNO', 'NOT IN', $exceptionEntries ];
                }
                $params = [
                    'selects' => ['RECORDNO'],
                    'filters' => [ $filters ]
                ];

                $params['isCaseInsensitive'] = true;

                $resultSet = $ccEntryManager->GetList($params);

                //Populate skipRecordNo list to skip
                foreach ($resultSet as $deleteRecords){
                    $skipRecordNo[] = $deleteRecords['RECORDNO'];
                }

            } else if($selectionState === self::NONE_EXCEPT_SOME && is_array($exceptionEntries)
                && count($exceptionEntries) > 0){
                $skipRecordNo = $exceptionEntries;
            }
        }

        if( is_array($skipRecordNo) && count($skipRecordNo) > 0){

            $skipEntryRecords = PrepINClauseStmt('', $skipRecordNo, " AND record#",
                true,'skipcyclecountentry');

            $skipEntryQuery = "UPDATE iccyclecountentry
                SET linecountstate   = 'S',
                     quantitycounted = '',
                     quantitydamaged = '', 
                     countedbykey    = ''
                WHERE cyclecountkey = :1
                AND linecountstate   in ('N', 'C') 
                $skipEntryRecords
                AND cny# = :2";

            $ok = $ok && ExecStmt([ $skipEntryQuery, $cycleCountRecordNo, GetMyCompany() ]);

        }

        return $ok;
    }

    /**
     * verifySkipCycleCountEntries check if any Counted Entries are being skipped and warn user.
     * @param array $requestParams
     *
     *
     * @return bool
     */
    protected function verifySkipCycleCountEntries($requestParams)
    {
        $countedEntries = false;
        $params = [];
        $ccMgr = Globals::$g->gManagerFactory->getManager( 'iccyclecount' );

        //State of selection ALL or ALL_EXCEPT_SOME or NONE_EXCEPT_SOME
        $selectionState = $requestParams['SELECTIONSTATE'];

        //ExceptionEntries are the entries based on the SELECT type.
        // If the state is ALL, then it will be empty means delete all entries.
        // If the state is ALL_EXCEPT_SOME, then we should delete all other entries except which are in the exceptionEntries.
        // If the state is NONE_EXCEPT_SOME, then delete all entries which are in the exceptionEntries.
        $exceptionEntries = $requestParams['EXCEPTIONENTRIES'];

        if(isset($selectionState)){
            $ccEntryManager = $this->GetManager('iccyclecountentry');
            if($selectionState === self::ALL || $selectionState === self::ALL_EXCEPT_SOME){
                $filters = [];

                $filterArray = $ccMgr->getFilters($requestParams, false);
                if( is_array($filterArray) && count($filterArray) > 0){
                    // Get the fields filters for the seletion State All and feild filter selected.
                    //or else it will delete the other records which it should not delete. Avoiding it by adding
                    // Fields filters.
                    $filters = $filterArray;
                }
                if($selectionState === self::ALL_EXCEPT_SOME && is_array($exceptionEntries)
                    && count($exceptionEntries) > 0 ){
                    $filters[] = [ 'RECORDNO', 'NOT IN', $exceptionEntries ];
                }
                $params = [
                    'selects' => ['LINECOUNTSTATE'],
                    'filters' => [ $filters ]
                ];
            } else if($selectionState === self::NONE_EXCEPT_SOME && is_array($exceptionEntries)
                && count($exceptionEntries) > 0){
                $filters[] = [ 'RECORDNO', 'IN', $exceptionEntries ];

                $params = [
                    'selects' => ['LINECOUNTSTATE'],
                    'filters' => [ $filters ]
                ];
            }

            $params['isCaseInsensitive'] = true;

            $cycleCountEntries = $ccEntryManager->GetList($params);
            if( is_array($cycleCountEntries) && count($cycleCountEntries) > 0){
                foreach ($cycleCountEntries as $cycleCountEntry){
                    if($cycleCountEntry['LINECOUNTSTATE'] == 'Counted'){
                        $countedEntries = true;
                        break;
                    }
                }
            }
        }

        return $countedEntries;
    }


    /**
     * removeCycleCountEntries will remove the selected cycle count entries
     * @param array $requestParams
     *
     * @return bool
     */
    protected function removeCycleCountEntries($requestParams)
    {
        $ok = true;
        $deleteRecordNo = [];
        $ccMgr = Globals::$g->gManagerFactory->getManager( 'iccyclecount' );

        //State of selection ALL or ALL_EXCEPT_SOME or NONE_EXCEPT_SOME
        $selectionState = $requestParams['SELECTIONSTATE'];

        //ExceptionEntries are the entries based on the SELECT type.
        // If the state is ALL, then it will be empty means delete all entries.
        // If the state is ALL_EXCEPT_SOME, then we should delete all other entries except which are in the exceptionEntries.
        // If the state is NONE_EXCEPT_SOME, then delete all entries which are in the exceptionEntries.
        $exceptionEntries = $requestParams['EXCEPTIONENTRIES'];

        if(isset($selectionState)){
            $ccEntryManager = $this->GetManager('iccyclecountentry');
            if($selectionState === self::ALL || $selectionState === self::ALL_EXCEPT_SOME){
                $filters = [];
                $filterArray = $ccMgr->getFilters($requestParams, false);
                if( is_array($filterArray) && count($filterArray) > 0){
                    // Get the fields filters for the seletion State All and feild filter selected.
                    //or else it will delete the other records which it should not delete. Avoiding it by adding
                    // Fields filters.
                    $filters = $filterArray;
                }
                if(($selectionState === self::ALL_EXCEPT_SOME) && is_array($exceptionEntries)
                   && count($exceptionEntries) > 0 ){
                    $filters[] = [ 'RECORDNO', 'NOT IN', $exceptionEntries ];
                }
                $params = [
                    'selects' => ['RECORDNO'],
                    'filters' => [ $filters ]
                ];

                $params['isCaseInsensitive'] = true;

                $resultSet = $ccEntryManager->GetList($params);

                //Populate deleteRecordNo list to skip
                foreach ($resultSet as $deleteRecords){
                    $deleteRecordNo[] = $deleteRecords['RECORDNO'];
                }

            } else if($selectionState === self::NONE_EXCEPT_SOME && is_array($exceptionEntries)
                && count($exceptionEntries) > 0){
                $deleteRecordNo = $exceptionEntries;
            }
        }

        if( is_array($deleteRecordNo) && count($deleteRecordNo) > 0){
            $ccEntryManager = $this->GetManager('iccyclecountentry');
            foreach ($deleteRecordNo as $deleteRecords){
                $ok = $ok && $ccEntryManager->Delete($deleteRecords);
            }

            //Extra logic to update lineincount, no other way we can do it.
            $cycleCountRecordNo = $requestParams['CYCLECOUNTKEY'];
            $getLinesCountQry = "SELECT
                                    COUNT(1) AS linesincount
                                FROM
                                    iccyclecountentry
                                WHERE
                                    cyclecountkey = :1
                                    AND cny# = :2";
            $res = QueryResult([ $getLinesCountQry, $cycleCountRecordNo, GetMyCompany() ]);
            $count = $res[0]['LINESINCOUNT'];

            $updateLinesCountQry = "UPDATE iccyclecount
                                    SET
                                        linesincount = :1
                                    WHERE
                                        record# = :2
                                        AND cny# = :3";
            $ok = $ok && ExecStmt([ $updateLinesCountQry, $count, $cycleCountRecordNo, GetMyCompany() ]);
        }

        return $ok;
    }


    /**
     * validateFIFICycleCountEntry will remove the selected cycle count entries
     * @param array $requestParams
     *
     * @return bool
     */
    protected function validateFIFOLIFOEntry($requestParams)
    {
        $ok = true;
        $cycleCountRecordNo = $requestParams['CYCLECOUNTKEY'];
        if(isset($cycleCountRecordNo)) {
            $ccEntryManager = $this->GetManager('iccyclecountentry');
            $filters = array(
                'filters' => array(array(
                    array('CYCLECOUNTKEY', '=', $cycleCountRecordNo),
                    array('actualadj', '>', 0),
                    array('unitcost', '=', 0),
                    array('cost_method', 'IN', array('F', 'L'))
                ))
            );

            $result = $ccEntryManager->GetCount($filters);
            if($result > 0){
                $ok = false;
            }
        }

        return $ok;
    }

    /**
     * additionalCycleCountEntry add the Additional  cycle count entry
     * @param array $requestParams
     *
     * @return array
     */
    protected function additionalCycleCountEntry($requestParams)
    {
        $ok = true;
        $additionalEntry = [];
        $gQueryMgr = Globals::$g->gQueryMgr;
        $gManagerFactory = Globals::$g->gManagerFactory;
        $kINVid = &Globals::$g->kINVid;
        GetModulePreferences($kINVid, $invPrefs);
        $companyid = GetMyCompany();
        $data = [];
        $skipCountEntries = false;

        $item           = $requestParams['ADDITEMID'];
        $binId          = $requestParams['ADDBINID'];
        $serialNo       = $requestParams['ADDSERIALNO'];
        $lotNo          = $requestParams['ADDLOTNO'];
        $expirationdDate   = $requestParams['ADDEXPIRATIONDATE'];
        $cycleCountRecordNo  = $requestParams['CYCLECOUNTKEY'];
        $countedbyId         = $requestParams['ADDCOUNTEDBYID'];
        $warehouseKey        = $requestParams['WAREHOUSEKEY'];

        $ccMgr = $gManagerFactory->getManager( 'iccyclecount' );

        if ( ! is_object($this->entityMgr) ) {
            $this->entityMgr = $this->GetManager($this->getEntity());
        }

        //Additional item details need to fetch.
        if(isset($item) && $item != ''){
            $itemID[] = explode('--', $item)[0];
            $itemQuery = array('QUERY' => "SELECT
                                            item.itemid          ITEMID,
                                            item.record#         ITEMKEY,
                                            icuom.unit           ITEMUNIT,
                                            item.productlinekey  PRODUCTLINE,
                                            icitemwhse.cycle     ITEMCYCLE
                                            FROM
                                            icitem         item,
                                            icprodline     ip,
                                            icuomgrp,
                                            icuom,
                                            icitemwhse
                                            WHERE item.cny# = ?
                                            AND item.cny# = icuomgrp.cny#
                                            AND item.uomgrpkey = icuomgrp.record#
                                            AND icuomgrp.cny# = icuom.cny#
                                            AND icuom.isbase = 'T'
                                            AND icuom.grpkey = icuomgrp.record#
                                            AND item.cny# = ip.cny# (+)
                                            AND item.productlinekey = ip.productlineid (+)
                                            AND item.itemtype IN ( 'I', 'SK' )
                                            AND item.cny# = icitemwhse.cny# (+)
                                            AND item.itemid = icitemwhse.itemkey (+)
                                            AND item.itemid = ?",
                                'ARGTYPES' => array('integer', 'text'));
            $itemArgs = array($companyid, $itemID[0]);
            $itemResults = $gQueryMgr->DoCustomQuery($itemQuery, $itemArgs, true);

            if(is_array($itemResults) && count($itemResults) > 0){
                $additionalEntry['ITEMID'] = $itemResults[0]['ITEMID'];
                $additionalEntry['ITEMKEY'] = $itemResults[0]['ITEMKEY'];
                $additionalEntry['ITEMUNIT'] = $itemResults[0]['ITEMUNIT'];
                $additionalEntry['PRODUCTLINE'] = $itemResults[0]['PRODUCTLINE'];
                $additionalEntry['ITEMCYCLE'] = $itemResults[0]['ITEMCYCLE'];
                $additionalEntry['QUANTITYONHAND'] = 0;
            }

            //Logic to fetch the on hand quantity for Add item.
            $fetchOnHandQuery = array('QUERY' => "SELECT
                                                    itmhistcost.qtyonhand QUANTITYONHAND
                                                    FROM
                                                    icitem         item,
                                                    icitemwhse,
                                                    itmhistcost
                                                    WHERE item.cny# = ?
                                                    AND item.itemtype IN ( 'I', 'SK' )
                                                    AND item.cny# = icitemwhse.cny# (+)
                                                    AND item.itemid = icitemwhse.itemkey (+)
                                                    AND item.itemid = ?
                                                    AND itmhistcost.cny# = item.cny# (+)
                                                    AND itmhistcost.itemkey = item.itemid (+)
                                                    AND itmhistcost.whsekey = ?
                                                    AND ason = (SELECT MAX(ason)
                                                                FROM
                                                                itmhistcost itmhistcost1
                                                                WHERE
                                                                 itmhistcost1.cny# = ?
                                                                 AND itmhistcost1.itemkey = ?
                                                                 AND itmhistcost1.whsekey = ?)",
                                        'ARGTYPES' => array('integer', 'text', 'text', 'integer', 'text', 'text'));
            $fetchOnHandArgs = array($companyid, $itemID[0], $warehouseKey, $companyid, $itemID[0], $warehouseKey);
            $fetchOnHandResults = $gQueryMgr->DoCustomQuery($fetchOnHandQuery, $fetchOnHandArgs, true);

            if(is_array($fetchOnHandResults) && count($fetchOnHandResults) > 0){
                $additionalEntry['QUANTITYONHAND'] = $fetchOnHandResults[0]['QUANTITYONHAND'];
            }

            //Prepairing BIN, SERIAL NUMBER and LOT NUMBER information if required or else we ignore it.
            $itemMgr = $gManagerFactory->getManager('item');
            $itemFilter = array(
                'selects' => array('ENABLEBIN', 'ENABLESNO', 'ENABLELOT', 'SERIALMASKKEY', 'ENABLEEXPIRATION'),
                'filters' => array (array (array('ITEMID', '=', $itemID[0]))),
            );

            $itemTrackingDetails = $itemMgr->GetList($itemFilter);

            //Additional bin details need to fetch.
            if(isset($binId) && $binId != ''){
                $binMgr = $gManagerFactory->getManager('bin');
                $filter = array(
                    'selects' => array('RECORDNO', 'BINID', 'AISLEKEY', 'AISLEID', 'ROWKEY', 'ROWID', 'ZONEKEY', 'ZONEID'),
                    'filters' => array(array(array('BINID', '=', $binId)))
                );
                $binResults = $binMgr->GetList($filter);
                if(is_array($binResults) && count($binResults) > 0){
                    $additionalEntry['BINKEY'] = $binResults[0]['RECORDNO'];
                    $additionalEntry['BINID'] = $binResults[0]['BINID'];
                    $additionalEntry['AISLEKEY'] = $binResults[0]['AISLEKEY'];
                    $additionalEntry['AISLEID'] = $binResults[0]['AISLEID'];
                    $additionalEntry['ROWKEY'] = $binResults[0]['ROWKEY'];
                    $additionalEntry['ICROWID'] = $binResults[0]['ROWID'];
                    $additionalEntry['ZONEKEY'] = $binResults[0]['ZONEKEY'];
                    $additionalEntry['ZONEID'] = $binResults[0]['ZONEID'];
                    $additionalEntry['QUANTITYONHAND'] = 0;
                }
            } else {
                if($itemTrackingDetails[0]['ENABLEBIN'] =='T' && $invPrefs['ENABLEBIN'] == 'T'){
                    $data['blankbin'] = 'Y';
                    $ok = false;
                }
            }

            if($ok){
                //Additional serialNo details added here.
                if(isset($serialNo) && $serialNo != ''){
                    if(isset($itemTrackingDetails[0]['SERIALMASKKEY']) && $itemTrackingDetails[0]['SERIALMASKKEY'] != ''){
                        $serialMaskMgr = $gManagerFactory->getManager('serialmask');
                        $serialMaskFilter = array(
                            'selects' => array('MASK'),
                            'filters' => array (array (array('RECORDNO', '=', $itemTrackingDetails[0]['SERIALMASKKEY']))),
                        );
                        $serialMasks = $serialMaskMgr->GetList($serialMaskFilter);
                        if(isset($serialMasks[0]['MASK']) && $serialMasks[0]['MASK'] != ''){
                            $trackingHandlers = new TrackingHandler(array('ACTION' => EDIT_ACTION));
                            $maskPattern = $trackingHandlers->PrepSerialMaskRegExPattern($serialMasks[0]['MASK']);
                            if(isset($maskPattern) && $maskPattern!='') {
                                $serialMaskNoQuotes   = str_replace("'", "", $serialMasks[0]['MASK']);    // remove the single quotes
                                if (!preg_match($maskPattern, $serialNo) || strlen($serialMaskNoQuotes)!=strlen($serialNo)) {
                                    $data['serialnoerr'] = 'Y';
                                    $data['serialnomask'] = $serialMasks[0]['MASK'];
                                    $ok = false;
                                }
                            }
                        }
                    }
                    $additionalEntry['SERIALNO'] = $serialNo;
                    $additionalEntry['QUANTITYONHAND'] = 0;
                } else {
                    if($itemTrackingDetails[0]['ENABLESNO'] =='T' && $invPrefs['ENABLESERIAL'] == 'T'){
                        $data['blankserialno'] = 'Y';
                        $ok = false;
                    }
                }
            }

            if($ok){
                //Additional lotNo details added here.
                if(isset($lotNo) && $lotNo != ''){
                    $additionalEntry['LOTNO'] = $lotNo;
                    $additionalEntry['QUANTITYONHAND'] = 0;
                } else {
                    if($itemTrackingDetails[0]['ENABLELOT'] =='T' && $invPrefs['ENABLELOT'] == 'T'){
                        $data['blanklotno'] = 'Y';
                        $ok = false;
                    }
                }
            }

            if($ok){
                //Additional EXPIRATIONDATE details added here.
                if(isset($expirationdDate) && $expirationdDate != ''){
                    $additionalEntry['EXPIRATIONDATE'] = $expirationdDate;
                    $additionalEntry['QUANTITYONHAND'] = 0;
                } else {
                    if($itemTrackingDetails[0]['ENABLEEXPIRATION'] =='T' && $invPrefs['ENABLE_EXPIRATION'] == 'T'){
                        $data['blankexpdate'] = 'Y';
                        $ok = false;
                    }
                }
            }

            if($ok){
                //Prepare uniquekey for skipping validation.
                $additionalEntry['UNIQUEPROPONROW'] = $additionalEntry['ITEMKEY'] .
                                                      '#' . $additionalEntry['BINKEY'].
                                                      '#' . $serialNo .
                                                      '#' . $lotNo.$expirationdDate;

                //Check for the entry which exist already present in this current cycle count
                $ccEntryManager = $this->GetManager('iccyclecountentry');

                if(isset($serialNo) && $serialNo != ''){
                    $data['isserial'] = 'Y';
                    $ccyclecountparams = array(
                        'selects' => array('RECORDNO'),
                        'filters' => array (
                            array (
                                array( 'CYCLECOUNTKEY', '=', $cycleCountRecordNo),
                                array( 'ITEMID', '=', $itemID[0]),
                                array( 'SERIALNO', '=', $serialNo)
                            ),
                        )
                    );
                } else {
                    $ccyclecountparams = array(
                        'selects' => array('RECORDNO'),
                        'filters' => array (
                            array (
                                array( 'CYCLECOUNTKEY', '=', $cycleCountRecordNo),
                                array( 'UNIQUEPROPONROW', '=', $additionalEntry['UNIQUEPROPONROW'])
                            ),
                        )
                    );
                }

                $existEntryRecords = $ccEntryManager->GetList($ccyclecountparams);

                if (count($existEntryRecords) > 0){
                    $data['entryexist'] = 'Y';
                    $ok = false;
                }

                if ($ok) {
                    //Get the physical Inventory data Qty Onhand if this item exist in it. So be concistant in both Add items
                    // and Select Items.
                    $requestParams['UNIQUEKEYS'][] = $additionalEntry['UNIQUEPROPONROW'];
                    $cycleCountData = $ccMgr->executeCycleCountQuery($warehouseKey, false, true, $requestParams);
                    if (is_array($cycleCountData) && count($cycleCountData) > 0 && isset($cycleCountData[0]['QUANTITYONHAND'])) {
                        $additionalEntry['QUANTITYONHAND'] = $cycleCountData[0]['QUANTITYONHAND'];
                    } else if (!is_array($cycleCountData) && $cycleCountData === false) {
                        // return false in case of query error
                        $ok = false;
                    }

                    if ($ok) {
                        $additionalEntryData = array($additionalEntry);
                        $obj = $this->entityMgr->get($cycleCountRecordNo);

                        if (isset($obj['COUNTSTATE']) && $obj['COUNTSTATE'] == self::STATE_INPROGRESS_VALUE) {
                            $skipCountEntries = $ccMgr->getSkipCycleCountList($additionalEntryData, $warehouseKey);
                        }

                        if (is_array($additionalEntryData) && count($additionalEntryData) > 0) {
                            //populate default data so that it can be used for filtering
                            foreach ($additionalEntryData as $key => $selectedRow) {
                                if ($additionalEntryData[$key]['LINECOUNTSTATE'] !== 'Skipped') {
                                    $additionalEntryData[$key]['COUNTEDBYID'] = $countedbyId;
                                    $additionalEntryData[$key]['LINECOUNTSTATE'] = 'Not Counted';
                                }
                            }
                            $obj['CYCLECOUNTENTRY'] = array_merge(is_array($obj['CYCLECOUNTENTRY']) ? $obj['CYCLECOUNTENTRY'] : [], $additionalEntryData);
                            $obj['LINESINCOUNT'] = Util::countOrZero($obj['CYCLECOUNTENTRY']);
                            $ok = $ok && $this->entityMgr->set($obj);
                        }
                    }
                }

                if($ok && $skipCountEntries){
                    $data['skipped'] = 'skipped';
                }
            }
        } else {
            $data['blankitem'] = 'Y';;
            $ok = false;
        }

        //Preparing resul so that we can show proper error message
        $data['result'] = $ok;
        return $data;
    }


    /**
     * itemDetailsFetch add the Additional  cycle count entry
     *
     * @return array
     */
    protected function itemDetailsFetch()
    {
        $kINVid = &Globals::$g->kINVid;
        GetModulePreferences($kINVid, $invPrefs);
        $gManagerFactory = Globals::$g->gManagerFactory;
        $changedItemId = Request::$r->{'_changedItemId'};
        $changedItemDetails = [];
        $returnData = ['ENABLEBIN'=> 'F', 'ENABLESNO'=> 'F', 'ENABLELOT'=> 'F', 'ENABLEEXPIRATION'=> 'F' ];

        if ( ! is_object($this->entityMgr) ) {
            $this->entityMgr = $this->GetManager($this->getEntity());
        }

        //Additional item details need to fetch.
        if(isset($changedItemId) && $changedItemId != ''){
            //Prepairing BIN, SERIAL NUMBER and LOT NUMBER information if required or else we ignore it.
            $itemMgr = $gManagerFactory->getManager('item');
            $itemFilter = array(
                'selects' => array('ENABLEBIN', 'ENABLESNO', 'ENABLELOT', 'ENABLEEXPIRATION'),
                'filters' => array (array (array('ITEMID', '=', $changedItemId))),
            );
            $changedItemDetails = $itemMgr->GetList($itemFilter);
        }

        if($changedItemDetails[0]){
            if($changedItemDetails[0]['ENABLEBIN'] == 'T' && $invPrefs['ENABLEBIN'] == 'T'){
                $returnData['ENABLEBIN'] = 'T';
            }

            if($changedItemDetails[0]['ENABLESNO'] == 'T' && $invPrefs['ENABLESERIAL'] == 'T'){
                $returnData['ENABLESNO'] = 'T';
            }

            if($changedItemDetails[0]['ENABLELOT'] == 'T' && $invPrefs['ENABLELOT'] == 'T'){
                $returnData['ENABLELOT'] = 'T';
            }

            if($changedItemDetails[0]['ENABLEEXPIRATION'] == 'T' && $invPrefs['ENABLE_EXPIRATION'] == 'T'){
                $returnData['ENABLEEXPIRATION'] = 'T';
            }
        }

        return $returnData;
    }

    /**
     * Check if batch can be edited
     *
     * @return bool false if multi-entity company and batch is not owned by the current location, otherwise true
     */
    protected function CanEdit()
    {
        $result = parent::CanEdit();

        if(!$result) {
            return $result;
        }

        $ccMgr = Globals::$g->gManagerFactory->getManager( 'iccyclecount' );
        $recordNo = Request::$r->_r;

        if (isset( $recordNo ) && $recordNo != '') {
            $result = $ccMgr->canEdit( $recordNo );
        }

        return $result;
    }

    /**
     * @return bool
     */
    protected function getShowRepeatMsg()
    {
        return false;
    }
    /**
     * Figure out if we can CanPrint
     *
     * @return bool true if we can print else false
     */
    protected function CanPrint()
    {
        $ok = true;

        //Chec k for the state print worksheet shoud be availble only if the Cycle cout state is In progress/ Completed.
        $state = Request::$r->GetCurrentObjectValueByPath('COUNTSTATE');
        $countStates = [ self::STATE_NOTSTARTED_VALUE, self::STATE_RECONCILED_VALUE, self::STATE_VOIDED_VALUE ];
        if( isset($state) && in_array($state, $countStates) ) {
            $ok = false;
        }

        return $ok;
    }

    /**
     * Get the excel URL for a Journal Entry
     *
     * @return string the print URL
     */
    protected function getCurrentExcelURL()
    {
        $url = '';
        $sess = Session::getKey();
        $op = GetOperationId('inv/reports/iccyclecount');
        $cycleCountRecordNo = Request::$r->_r;

        if($cycleCountRecordNo){
            // Set the new excel URL with all the dimensions
            $url = 'reportor.phtml?.op=' . $op . '&.cycleCountRecordNo=' . $cycleCountRecordNo. '&.type=_excel' .
                '&.sess=' . $sess;
        }

        return $url;
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function transformBizObjectToView(&$obj)
    {
        $ok = parent::transformBizObjectToView($obj);

        $ok = $ok && $this->populateDimValuesToHeader($obj);

        return $ok;
    }

    /**
     * Function to populate Standard Dimension Values from Cycle count Entries To Cycle count Header
     * @param array $obj
     *
     * @return bool
     */
    protected function populateDimValuesToHeader(&$obj)
    {
        if( isset($obj['COUNTSTATE']) && $obj['COUNTSTATE'] === self::STATE_RECONCILED_VALUE ) {
            $dimFields = $this->getCyclecountEntryDimensions($params);
            if (is_array($obj['CYCLECOUNTENTRY'])) {
                foreach ($obj['CYCLECOUNTENTRY'] as $val) {
                    if (isset($val['DOCHDRKEY'])) {
                        //populating standard dimensions to the Cycle count header
                        foreach ($dimFields as $field) {
                            $obj[$field['path']] = $val[$field['path']];
                        }
                        $obj['DEPARTMENTID'] = $val['DEPARTMENTID'];

                        //populating custom dimensions to the Cycle count header
                        $this->populateCustomDimValuesToHeader($obj, $val['CUSTOMDIMENSIONS']);

                        //All the line entries in the document will have same dimensions,
                        // So we are populating only from the first line.
                        break;
                    }
                    /*foreach ($dimFields as $field) {
                        unset($val[$field['path']]);
                    }*/
                }
            }
        }

        return true;
    }

    /**
     * Function to populate Custom Dimension Values from Cycle count Entries To Cycle count Header
     * @param array $obj
     * @param string $entryCustomDimesionValue
     *
     * @return bool
     */
    private function populateCustomDimValuesToHeader(&$obj, $entryCustomDimesionValue)
    {
        $customDimensionEntry = [];
        if ( !util_isPlatformDisabled() && IADimensions::isCustomDimensionsEnabled() ) {
            $customDimensionEntry["CUSTOMDIMENSIONS"] = $entryCustomDimesionValue;
            IADimensions::explodeCustomDimensionString($customDimensionEntry);
            unset($customDimensionEntry["CUSTOMDIMENSIONS"]);
        }

        if (count($customDimensionEntry) > 0) {
            foreach ( $customDimensionEntry as $custFieldKey => $custField){
                $obj[$custFieldKey] = $custField;
                $data = Pt_DataObjectManager::getById2($obj[$custFieldKey]);
                $obj[$custFieldKey. '_disp'] = (string)$data;
            }
        }

        return true;
    }

    /**
     * Merge dimension fields in the UI
     *
     * @param array $_params
     */
    protected function MergeOwnerDimensions(&$_params)
    {
        parent::MergeOwnerDimensions($_params);
        $this->mergeCyclecountEntryDimensions($_params);
    }

    /**
     * Function to merge Cyclecount Entry Dimensions To Cycle count Header
     *
     * @param array         $params
     *
     * @return bool
     */
    private function mergeCyclecountEntryDimensions(&$params)
    {
        $matches = array();
        self::findElements($params, array('id' => 'CYCLECOUNT_DIMENSIONS'), EditorComponentFactory::TYPE_SECTION, $matches);
        if (is_array($matches) && !empty($matches)) {
            $section =& $matches[0];
            $stdDims = array();
            if (departmentsExist()) {
                $stdDims[] = array(
                    'path' => 'DEPARTMENTID'
                );
            }

        } else {
            return false;
        }

        $fields = $this->getCyclecountEntryDimensions($params);

        $fields = INTACCTarray_merge($stdDims, $fields);
        $section = array(
            'title' => GT($this->textMap, 'IA.CYCLE_COUNT_DIMENSIONS'),
            'id' => 'CYCLECOUNT_DIMENSIONS',
            "isCollapsible" => true,
            "showCollapsed" => true,
            'subsection' => array(
                                array(
                                    'className' => "subSection qx-cfg-subsection",
                                    'title' => '',
                                    'columnCount' => 3,
                                    'field' => $fields
                                ),
            )

        );

        return true;
    }

    /**
     * Function to get Cyclecount Entry Dimensions
     *
     * @param array     $_params
     *
     * @return array
     */
    private function getCyclecountEntryDimensions(&$_params)
    {
        $primaryDim = $this->getEntityMgr()->getPrimaryDimensions();
        if (is_array($primaryDim)) {
            foreach ($primaryDim as $dimPath => $fieldPath) {
                $_params['view']['primaryDimensions'][$dimPath] = $fieldPath;
            }
        }
        $nodes = $this->getDefaultsDimensionsFields($_params, 'iccyclecountentry');
        return $nodes;
    }

    /**
     * This function can be overriden if no default dimension fields are wanted
     *
     * @return bool
     */
    protected function isShowGridDefaults()
    {
        return false;
    }

    /**
     * Prepare the view for customization and hide all the Cyclecount Entry Dimensions in the grid.
     */
    protected function processViewBeforePageCustomzations()
    {
        // Get the view
        $view = $this->getView();

        //Logic to hide dimensions from the grid
        $matches = array();
        $view->findComponents(array('path' => 'CYCLECOUNTENTRY'), EditorComponentFactory::TYPE_GRID, $matches);
        $gridObj = &$matches[0];

        $fields = $this->getCyclecountEntryDimensions($params);

        foreach ($fields as &$field) {
            $matches = array();
            $gridObj->findComponents(array('path' => $field['path']), EditorComponentFactory::TYPE_FIELD, $matches);
            if ($matches) {
                $matches[0]->setProperty('hidden', true);
            }
        }
    }

    /**
     *  Function to populate Cyclecount Entry Dimensions from Cycle count Header
     *
     * @param array $_params
     * @param array|false $obj
     *
     * @return bool
     */
    function populateDimValuesForEntries($_params, &$obj)
    {
        $ok = true;
        $dimFields = $this->getCyclecountEntryDimensions($_params);
        foreach ($obj['CYCLECOUNTENTRY'] as &$ccEntries) {
            foreach ($dimFields as $field) {
                list($dimID) = explode("--", $obj[$field['path']]);
                $ccEntries[$field['path']] = $dimID;
            }
            list($depID) = explode("--", $obj['DEPARTMENTID']);
            $ccEntries['DEPARTMENTID'] = $depID;
        }

        return $ok;
    }

    /**
     * mediateDataAndMetadata_Fulfillment
     *
     *
     */
    protected function mediateDataAndMetadata_Fulfillment()
    {
        $kINVid = &Globals::$g->kINVid;
        GetModulePreferences($kINVid, $invPrefs);
        if ($invPrefs['ENABLEFULFILLMENT'] === 'T') {
            $view = $this->getView();
            $view->findAndSetProperty(
                array('id' => 'headerItems'), array('columnCount' => 4), EditorComponentFactory::TYPE_SUBSECTION
            );
            $view->findAndSetProperty(array('path' => 'EXCLUDEALLOCATEDQTY'), array('hidden' => false));
        }
    }

    /**
     * I18N. Collection of tokens used primarily in JavaScript.
     *
     * @return string[]
     */
    protected function getFormTokens(): array
    {
        $this->textTokens = array_merge($this->textTokens, ['IA.SELECT_AT_LEAST_ONE_ITEM','IA.CLICK_SELECT_ITEMS_BUTTON_TO_INCLUDE_IN_THIS_CYCLE_COUNT',
        'IA.NO_ITEMS_FOUND_MATCHING_YOUR_SEARCH_CRITERIA','IA.ENTER_A_POSITIVE_NUMBER_OR_ZERO_TO_CONTINUE','IA.PROVIDED_VALUE_IS_NOT_A_NUMBER',
        'IA.ENTERED_VALUES_EXCEEDS_THE_LIMIT_OF_10','IA.ENTER_A_POSITIVE_NUMBER_OR_ZERO_FOR_DAMAGE_ADJ','IA.ENTER_A_VALUE_1_FOR_QTY_COUNTED_OR_QTY_DAMAGED',
        'IA.ENTER_1_OR_0_OR_1_FOR_ADJ_OR_1_OR_0_FOR_DAMAGE','IA.ENTER_1_OR_0_OR_1_FOR_ADJUSTMENT_OR_DAMAGE','IA.SOMETHING_WENT_WRONG_PLS_TRY_AGAIN_IN_SOME_TIME',
        'IA.A_SYSTEM_ERROR_OCCURRED_PLEASE_CONTACT_THE_ADMINISTRATOR','IA.ITEM_SELECTED_TO_COUNT_FROM_THIS_COUNT_SKIPPED',
        'IA.PLEASE_SELECT_ITEM_TO_ADD','IA.ITEM_ENABLED_FOR_BIN_TRACKING_ENTER_BIN_INFO','IA.ITEM_ENABLED_FOR_SERIAL_TRACKING_ENTER_SER_INFO',
        'IA.SERIAL_NO_DOESNT_MATCH_OF_THE_SERIAL_NO_MASK','IA.ITEM_ENABLED_FOR_LOT_TRACKING_ENTER_LOT_NO','IA.ITEM_ENABLED_FOR_EXPIRY_TRACKING_ENTER_EXPIRY',
        'IA.UNABLE_TO_ADD_ITEM_DUPLICATE_SERIAL_NUMBER','IA.ITEM_ALREADY_EXIST_IN_THE_CYCLE_COUNT','IA.SOMETHING_WENT_WRONG_PLEASE_TRY_AGAIN_IN_SOME_TIME',
        'IA.SELECT_VALID_EMPLOYEE_COUNTED_BY_CANT_BE_EMPTY','IA.SELECT_AT_LEAST_ONE_ITEM_TO_SKIP','IA.YOU_ARE_ABOUT_TO_SKIP_COUNTING_ITEMS',
        'IA.YOU_ARE_ABOUT_TO_SKIP_ONE_OR_MORE_ITEMS','IA.SOMETHING_WENT_WRONG_IN_SKIP_OP_TRY_AGAIN_LATER','IA.SELECT_AT_LEAST_ONE_ITEM_TO_REMOVE',
        'IA.YOU_ARE_ABOUT_TO_DELETE_ITEMS','IA.SOMETHING_WENT_WRONG_IN_REMOVE_OP_TRY_AGAIN_LATER','IA.THERE_ARE_SELECTED_ENTRIES_STILL_YOU_WANT_TO_CLOSE',
        'IA.PLEASE_SELECT_AN_ITEM_FIRST','IA.NO_RECORD_COUNT_RETURNED_FOR_CYCLECOUNT','IA.NO_ITEMS_FOUND_MATCHING_YOUR_SEARCH_CRITERIA',
        'IA.THERE_ARE_FEW_FIFO_SLASH_LIFO_ITEMS_WITH_0_QOH_ADJ_VALUE','IA.ITEM_IS_IN_INPROGRESS_STATE_MARKED_AS_SKIPPED','IA.ADD_ITEMS']);
        return parent::getFormTokens();
    }
}

