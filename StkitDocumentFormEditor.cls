<?php

//
//================================================================================
//	FILE:			StkitDocumentFormEditor.cls
//	AUTHOR:			Manoj Mahur & Sudeendra Ramesh
//	DESCRIPTION:	This class manages all activities associated to a RecurDocument objects.
//
//	(C)2000-2005, Intacct Corporation, All Rights Reserved
//
//	This document contains trade secret data that belongs to Intacct
//	corporation and is protected by the copyright laws. Information
//	herein may not be used, copied or disclosed in whole or part
//	without prior written consent from Intacct Corporation.
//================================================================================
//

/**
 * Class StkitDocumentFormEditor
 */
class StkitDocumentFormEditor extends DocumentFormEditor
{

    /** @var  array $_paramRows */
    var $_paramRows;

    /**
     * @param array $_params
     */
    public function __construct($_params) {
        $this->additionalTokens = [
            'IA.DISASSEMBLED_FROM',
            'IA.BUILT',
            'IA.DISASSEMBLED',
            'IA.DRAFT',
            'IA.EXTENDED_COST',
            'IA.WAREHOUSE',
            'IA.POST',
            'IA.CANCEL',
            'IA.POST_AND_NEW',
            'IA.DRAFT_AND_CONTINUE',
            'IA.EDIT',
            'IA.DONE',
            'IA.PRINT_TO',
            'IA.DETAILS',
            'IA.TRANSACTION',
        ];
        parent::__construct($_params);
    }

    /**
     * @param array $obj
     */
    protected function mediateDataAndMetadata_Header(&$obj)
    {

        parent::mediateDataAndMetadata_Header($obj);

        $view = $this->getView();

        $headersections = array();
        $view->findComponents(array('id' => 'mainPage'), EditorComponentFactory::TYPE_TAB, $headersections);
        $headersection = $headersections[0];

        $headersection->findAndSetProperty(array( 'path' => 'CREATEDFROM' ),
                                           array( 'fullname' => GT($this->textMap, 'IA.DISASSEMBLED_FROM')));

        if ( $this->dt == DIS_KIT ) {
            $headersection->findAndSetProperty(array('path' => 'STATE'), array('readonly' => true));
        }
    }

    /**
     * Return an Array of Javascript files to include into the page
     *
     * @return string[] The Javascript files to include
     */
    protected function getJavaScriptFileNames()
    {
        $jsFiles = parent::getJavaScriptFileNames();
        $jsFiles[] = '../resources/js/oeinvouttrackinggrid.js';
        $jsFiles[] = '../resources/js/stkittracking.js';

        return $jsFiles;
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    private function hasTracking($obj)
    {
        return ( isset($obj['SERIALNO']) || isset($obj['LOTNO']) || isset($obj['BINID']) || isset($obj['EXPIRATION']) );
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function transformViewObjectToBiz(&$obj)
    {
        $ok = parent::transformViewObjectToBiz($obj);

        //Walk the entries and transform the entries tracking data so the backend bizlogic can save the data
        if ($ok && StkitDocumentManager::isStockableKitTrackingEnabled()) {
            //Walk the ENTRIES grid and transform the data to biz object data
            foreach ($obj['ENTRIES'] as &$entry) {
                $entry['TRACKINGENTRIES'] = [];
                if (isset($entry['ITEMID'])) {
                    list($itemid) = explode('--', $entry['ITEMID']);

                    //Walk the sk build into grid and copy to backend TRACKINGENTRIES data structure
                    foreach ($entry['SKTRACKINGGRID'] as $skTracking) {
                        if ($this->hasTracking($skTracking)) {
                            $skTracking['ITEMID'] = $itemid;
                            $skTracking['QUANTITY'] = $skTracking['TRACK_QUANTITY'];
                            if (isset($skTracking['BINID'])) {
                                list($skTracking['BINID']) = explode('--', $skTracking['BINID']);
                            }
                            $entry['TRACKINGENTRIES'][] = $skTracking;
                        }
                    }

                    //Walk the component build out of grid and copy to biz object data structure
                    foreach ($entry['SKCOMPONENTGRID'] as $skComponent) {
                        if (isset($skComponent['COMPONENTID'])) {
                            foreach ($skComponent['SKCOMPONENTTRACKINGGRID'] as $skComponentTracking) {
                                if ($this->hasTracking($skComponentTracking)) {
                                    $skComponentTracking['ITEMID'] = $skComponent['COMPONENTID'];
                                    $skComponentTracking['COMPONENTID'] = $skComponent['COMPONENTID'];
                                    $skComponentTracking['QUANTITY'] = $skComponentTracking['TRACK_QUANTITY'];
                                    $entry['TRACKINGENTRIES'][] = $skComponentTracking;
                                }
                            }
                        }
                    }
                }
            }
        }

        return $ok;
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function transformBizObjectToView(&$obj)
    {
        $ok = parent::transformBizObjectToView($obj);

        if($ok) {
            //In edit state, when we reload from error, the state will be set as null so we need to preserve here
            //or the state will be incorrect and the UI controls will be incorrect as well
            if ($this->state === Editor_ShowEditState) {
                if (!isset($obj['LOADEDSTATE'])) {
                    $obj['LOADEDSTATE'] = $obj['STATE'];
                } else {
                    $obj['STATE'] = $obj['LOADEDSTATE'];
                }
            }

            // Override the state values to represent the kits.
            $summaryState = GT($this->textMap, 'IA.DRAFT');;
            if ($this->dt == DIS_KIT) {
                if ($obj['STATE'] == 'Pending') {
                    $obj['STATE'] = 'Disassembled';
                    $summaryState = GT($this->textMap, 'IA.DISASSEMBLED');
                } else if ($obj['STATE'] != DocumentManager::DRAFT_STATE) {
                    $obj['STATE'] = '';
                    $summaryState = '';
                }
            } else if ($this->dt == BUILD_KIT) {
                if ($obj['STATE'] == 'Converted') {
                    $obj['STATE'] = 'Disassembled';
                    $summaryState = GT($this->textMap, 'IA.DISASSEMBLED');
                } else if ($obj['STATE'] == 'Pending') {
                    $obj['STATE'] = 'Built';
                    $summaryState = GT($this->textMap, 'IA.BUILT');
                } else if ($obj['STATE'] == 'In Progress') {
                    //Purposely have nothing here
                } else if ($obj['STATE'] != DocumentManager::DRAFT_STATE) {
                    $obj['STATE'] = '';
                    $obj['STKITDOCLOADED'] = 'T';
                    $summaryState = '';
                }
            }
            $obj['SUMMARY']['STATE'] = $summaryState;


            //Walk the entries biz object data and transform to UI data structure
            if (!isset($obj['STKITDOCLOADED']) && StkitDocumentManager::isStockableKitTrackingEnabled()) {

                //Private function to help with finding a matching item in the passed in $entries
                //Returns -1 if no match, otherwise returns the index of the matching entry
                $findMatchIndex = function($entries, $entryPath, $matchStr) {
                    $foundMatch = -1;
                    foreach ($entries as $index => $entry) {
                        if ($entry[$entryPath] === $matchStr) {
                            $foundMatch = $index;
                            break;
                        }
                    }
                    return $foundMatch;
                };

                //Private function to help totaling the passed in $entryPath field in the passed in $entries
                $addEntries = function($entries, $entryPath) {
                    $total = 0;
                    foreach ($entries as $entry) {
                        $total = ibcadd($total, $entry[$entryPath],ItemManager::BASEUNITPRECISION,true);
                    }
                    return $total;
                };

                //Base on the state and build/disasembly txn, we need to use the correct dockey into the
                //docentrycostkits to know what SK components we used to build
                $docEntryPath = 'RECORDNO';
                if ($this->dt === DIS_KIT && ($obj['STATE'] === DocumentManager::DRAFT_STATE || $obj['STATE'] === '')) {
                    $docEntryPath = 'SOURCE_DOCLINEKEY';
                }

                //Read in the docentrycostkits (stored in $skComponentsSaved) for the ENTRIES so we can know what the skit definition we built with
                $docEntryKeys = [];
                foreach ($obj['ENTRIES'] as $entry) {
                    $docEntryKeys[] = $entry[$docEntryPath];
                }
                $qry = [];
                $qry[]  = "SELECT docentrykey, itemkey, quantity FROM docentrycostkits WHERE cny# = :1";
                $qry[]  = GetMyCompany();
                $qry = PrepINClauseStmt($qry, $docEntryKeys, " AND docentrykey ");
                $skComponents = QueryResult($qry);
                $skComponentsSaved = [];
                foreach ($skComponents as $skComponent) {
                    $key = $skComponent['ITEMKEY'].$skComponent['DOCENTRYKEY'];
                    $qty = isset($skComponentsSaved[$key]['QUANTITY'])? $skComponentsSaved[$key]['QUANTITY'] : 0;
                    $skComponent['QUANTITY'] = ibcadd($skComponent['QUANTITY'], $qty,ItemManager::BASEUNITPRECISION,true);
                    $skComponentsSaved[$key] = $skComponent;
                }

                //We need the latest SK kit definitions when we are in draft build
                $skDefinitions = [];
                if (count($skComponentsSaved) === 0 && $this->dt == BUILD_KIT && $obj['STATE'] === DocumentManager::DRAFT_STATE) {
                    $kits = [];
                    foreach ($obj['ENTRIES'] as $entry) {
                        list($kitId) = explode("--", $entry['ITEMID']);
                        $kits[] = $kitId;
                    }
                    $kitQry = [];
                    $kitQry[] = "SELECT kitcomp.itemkey kit, kitcomp.componentkey componentid, kitcomp.quantity, item.itemtype, item.enablesno, item.enablelot, item.enablebin, item.enableexpiration
                                FROM icitemcomponent kitcomp INNER JOIN icitem item ON item.cny# = kitcomp.cny# AND item.itemid = kitcomp.componentkey
                                WHERE kitcomp.cny# = :1";
                    $kitQry[]  = GetMyCompany();
                    $kitQry = PrepINClauseStmt($kitQry, $kits, " AND kitcomp.itemkey ");
                    $kits = QueryResult($kitQry);
                    foreach ($kits as $kit) {
                        $kitId = $kit['KIT'];
                        $skDefinitions[$kitId][] = $kit;
                    }
                }

                //This loop is where we actually walk each ENTRIES and transfer to UI data structure from
                //the TRACKINGENTRIES and the $skComponentsSaved data
                foreach ($obj['ENTRIES'] as &$entry) {
                    list($entryItemId) = explode('--', $entry['ITEMID']);
                    if (count($entry['TRACKINGENTRIES'] ?? [])) {
                        $entry['SKTRACKINGGRID'] = [];
                        $entry['SKCOMPONENTGRID'] = [];
                        $trackedSKComponents = [];

                        //Walk the TRACKINGENTRIES biz object and transfer to UI data for sk tracking portion
                        foreach ( $entry['TRACKINGENTRIES'] as $trackingEntry ) {
                            if ( $trackingEntry['ITEMID'] == $entryItemId ) {
                                $skTrackingEntry['SERIALNO'] = $trackingEntry['SERIALNO'];
                                $skTrackingEntry['LOTNO'] = $trackingEntry['LOTNO'];
                                $skTrackingEntry['BINID'] = $trackingEntry['BINID'];
                                $skTrackingEntry['EXPIRATION'] = $trackingEntry['EXPIRATION'];
                                $skTrackingEntry['TRACK_QUANTITY'] = $trackingEntry['TRACK_QUANTITY'];
                                $entry['SKTRACKINGGRID'][] = $skTrackingEntry;
                            } else {
                                //If we are drafting and the SK definition has changed, make sure the saved tracked components
                                //are still part of the SK definition
                                if ($this->dt === BUILD_KIT && $obj['STATE'] === DocumentManager::DRAFT_STATE
                                    && $findMatchIndex($skDefinitions[$entryItemId], 'COMPONENTID', $trackingEntry['ITEMID']) === -1) {
                                    continue;
                                }
                                $skComponentTrackingEntry['SERIALNO'] = $trackingEntry['SERIALNO'];
                                $skComponentTrackingEntry['LOTNO'] = $trackingEntry['LOTNO'];
                                $skComponentTrackingEntry['BINID'] = $trackingEntry['BINID'];
                                $skComponentTrackingEntry['EXPIRATION'] = $trackingEntry['EXPIRATION'];
                                $skComponentTrackingEntry['TRACK_QUANTITY'] = $trackingEntry['TRACK_QUANTITY'];
                                $componentId = $trackingEntry['ITEMID'];
                                $trackedSKComponents[$componentId]['SKCOMPONENTTRACKINGGRID'][] = $skComponentTrackingEntry;
                                $trackedSKComponents[$componentId]['COMPONENTID'] = $componentId;
                                $trackedSKComponents[$componentId]['TRACK_QUANTITY'] = ibcadd($trackedSKComponents[$componentId]['TRACK_QUANTITY'], $trackingEntry['TRACK_QUANTITY'],ItemManager::BASEUNITPRECISION,true);
                            }
                        }

                        //Walk the TRACKINGENTRIES biz object and transfer to UI data for sk component tracking
                        //portion which we setup in loop above
                        foreach ( $trackedSKComponents as $trackedSKComponent ) {
                            $trackedSKComponent['LINEITEMQTY'] = $entry['QUANTITY'];
                            $trackedSKComponent['COMPONENTITEMQTY'] = ibcdiv($trackedSKComponent['TRACK_QUANTITY'], $entry['QUANTITY'],ItemManager::BASEUNITPRECISION,true);
                            $trackedSKComponent['QUANTITY_NEEDED'] = $trackedSKComponent['TRACK_QUANTITY'];
                            $entry['SKCOMPONENTGRID'][] = $trackedSKComponent;
                        }
                    } else {
                        //No tracking entries and in draft, add an empty row to grid for the case where the user has yet to enter tracking data
                        if ($obj['STATE'] === DocumentManager::DRAFT_STATE) {
                            $entry['SKTRACKINGGRID'] = [[]];
                        }
                    }

                    //Walk the $skComponentsSaved and transfer to UI dara for sk component grid as this is the SK kit
                    //definition that was saved with bld/disassembly document
                    foreach ($skComponentsSaved as $skComponent) {
                        if ($entry[$docEntryPath] === $skComponent['DOCENTRYKEY'] && !isset($trackedSKComponents[$skComponent['ITEMKEY']])) {
                            $entry['SKCOMPONENTGRID'][] = ['COMPONENTID' => $skComponent['ITEMKEY'],
                                                           'LINEITEMQTY' => $entry['QUANTITY'],
                                                           'COMPONENTITEMQTY' => ibcdiv($skComponent['QUANTITY'], $entry['QUANTITY'],ItemManager::BASEUNITPRECISION,true),
                                                           'QUANTITY_NEEDED' => $skComponent['QUANTITY'],
                                                           'TRACK_QUANTITY' => $skComponent['QUANTITY']];
                        }
                    }

                    //Walk the $skDefinitions and transfer to UI dara for sk component grid as this is the SK kit latest
                    //definition defined in the item list
                    foreach ($skDefinitions[$entryItemId] as $skDefinitionComp) {
                        //We skip non-inv component
                        if ($skDefinitionComp['ITEMTYPE'] === 'NI' || $skDefinitionComp['ITEMTYPE'] === 'NS') {
                            continue;
                        }

                        //Look to see if the sk kit definition component is already in the component grid.
                        //If not in component grid, we add it.
                        $foundMatchIndex = $findMatchIndex($entry['SKCOMPONENTGRID'], 'COMPONENTID', $skDefinitionComp['COMPONENTID']);
                        if ($foundMatchIndex === -1) {
                            //Did not find a match, so we ADD.
                            $tmpQty = ibcmul($skDefinitionComp['QUANTITY'], $entry['QUANTITY'],ItemManager::BASEUNITPRECISION,true);
                            $draftBuildAndTrackedItem = ($this->dt === BUILD_KIT && $obj['STATE'] === DocumentManager::DRAFT_STATE
                                                        && ($skDefinitionComp['ENABLESNO'] === 'T' || $skDefinitionComp['ENABLELOT'] === 'T'
                                                            || $skDefinitionComp['ENABLEBIN'] === 'T' || $skDefinitionComp['ENABLEEXPIRATION'] === 'T'));
                            $entry['SKCOMPONENTGRID'][] = ['COMPONENTID' => $skDefinitionComp['COMPONENTID'],
                                                           'LINEITEMQTY' => $entry['QUANTITY'],
                                                           'COMPONENTITEMQTY' => $skDefinitionComp['QUANTITY'],
                                                           'QUANTITY_NEEDED' => $tmpQty,
                                                           'TRACK_QUANTITY' => $draftBuildAndTrackedItem? '' : $tmpQty,
                                                           'SKCOMPONENTTRACKINGGRID' => [[]]];
                        } else if ($this->dt === BUILD_KIT && $obj['STATE'] === DocumentManager::DRAFT_STATE) {
                            //Found a match in the component grid, so we MERGE.
                            $tmpQty = ibcmul($skDefinitionComp['QUANTITY'], $entry['QUANTITY'],ItemManager::BASEUNITPRECISION,true);
                            $entry['SKCOMPONENTGRID'][$foundMatchIndex]['COMPONENTID'] = $skDefinitionComp['COMPONENTID'];
                            $entry['SKCOMPONENTGRID'][$foundMatchIndex]['LINEITEMQTY'] = $entry['QUANTITY'];
                            $entry['SKCOMPONENTGRID'][$foundMatchIndex]['COMPONENTITEMQTY'] = $skDefinitionComp['QUANTITY'];
                            $entry['SKCOMPONENTGRID'][$foundMatchIndex]['QUANTITY_NEEDED'] = $tmpQty;
                            $tmpQty = $addEntries($entry['SKCOMPONENTGRID'][$foundMatchIndex]['SKCOMPONENTTRACKINGGRID'], 'TRACK_QUANTITY');
                            $entry['SKCOMPONENTGRID'][$foundMatchIndex]['TRACK_QUANTITY'] = $tmpQty;
                        }
                    }
                }

            }

            //So we don't transform biz object to UI data structure again
            $obj['STKITDOCLOADED'] = 'T';
        }

        return $ok;
    }

    /**
     * @param array $obj
     * @param array $docparmrec
     */
    protected function mediateDataAndMetadata_Entries(&$obj, $docparmrec)
    {
        parent::mediateDataAndMetadata_Entries($obj, $docparmrec);

        $view = $this->getView();

        $entriesViewArr = array();
        $view->findComponents(array('path' => 'ENTRIES'), EditorComponentFactory::TYPE_GRID, $entriesViewArr);
        $entriesView = $entriesViewArr[0];

        $entriesView->findAndSetProperty([ 'path' => 'WAREHOUSE.LOCATION_NO' ],
                                         [ 'fullname' => GT($this->textMap, 'IA.WAREHOUSE') ]);
        $UIValue_field = [];
        $entriesView->findComponents(array('path' => 'UIVALUE'), EditorComponentFactory::TYPE_FIELD, $UIValue_field);
        if (!is_null($UIValue_field) && !is_null($UIValue_field[0])){
            $extendedCostLabel=GT($this->textMap, 'IA.EXTENDED_COST');
            $UIValue_field[0]->setProperty('fullname', $extendedCostLabel);
            $UIValue_field[0]->setProperty('watermark',$extendedCostLabel);
        }

        // Override the state values to represent the kits.
        if ( $this->dt == DIS_KIT ) {
            $entriesView->setProperty('readonly', true);
            //$entriesView->findAndSetProperty(array('id' => 'itemDetails'), array('readonly' => true));
            $entriesView->propagateProperties(array('readonly' => true));
            $entriesView->findAndSetProperty(array('path' => 'WAREHOUSE.LOCATION_NO'), array('hidden' => true));
            $entriesView->findAndSetProperty(array('path' => 'DEPARTMENT'), array('hidden' => true));
            $entriesView->findAndSetProperty(array('path' => 'LOCATION'), array('hidden' => true));
        }

        $taskIsEnabledAsDimension = IADimensions::IsDimensionEnabled($this->mod, 'task');

        $matches = array();
        $entriesView->findComponents(array('path' => 'TASKID'), EditorComponentFactory::TYPE_FIELD, $matches);
        if (isset($matches[0]) && !$taskIsEnabledAsDimension) {
            foreach ($matches as $field) {
                $field->setProperty('hidden', false);
            }
        }
    }

    /**
     * @param array     $obj
     * @param int       $indx
     * @param array     $history
     * @param int       $totalLineCount
     *
     * @return bool
     */
    protected function setHistoryValuesByRow(&$obj, $indx, $history, $totalLineCount)
    {
        if ( $this->dt == BUILD_KIT || $this->dt == DIS_KIT ) {
            $state = $history['DOCSTATE'];
            $docid = '';
            if ( $history['DOCUMENTID'] ) {
                list($docid) = explode('-', $history['DOCUMENTID']);
            }
            if ( $docid == BUILD_KIT && $state == 'Converted' ) {
                $obj['HISTORY'][$indx]['DOCSTATE'] = GT($this->textMap, 'IA.DISASSEMBLED');
            } elseif ( $docid == BUILD_KIT && $state == 'Pending' ) {
                $obj['HISTORY'][$indx]['DOCSTATE'] = GT($this->textMap, 'IA.BUILT');
            } elseif ( $docid == DIS_KIT && $state == 'Pending' ) {
                $obj['HISTORY'][$indx]['DOCSTATE'] = GT($this->textMap, 'IA.DISASSEMBLED');
            }
        }
        return true;
    }

    // No restriction to this object.

    /**
     * @return array
     */
    protected function getItemPickRestrictParams()
    {
        return array();
    }

    /**
     * @return bool
     */
    protected function hideHistoryPage()
    {
        if ( $this->state == 'shownew' && $this->dt != DIS_KIT ) {
            return true;
        }
        return false;
    }

    /**
     * @return bool
     */
    protected function isShowGridDefaults()
    {
        if ( $this->dt == DIS_KIT ) {
            return false;
        }
        return true;
    }

    /**
     * @param array $obj
     * @param array $docparmrec
     */
    protected function mediateDataAndMetadata_Subtotals(&$obj, $docparmrec)
    {
    }

    /**
     * @param string $state
     *
     * @return array
     */
    public function getStandardButtons($state)
    {
        $values = array();
        $viewData = $this->getViewData();
        $draftMode = ($viewData['STATE'] == DocumentManager::DRAFT_STATE);

        switch ($state) {
            case Template_CreateWarningState:
            case Editor_ShowNewState:

                if ($this->CanSave()) {
                    $this->setButtonDetails($values, Editor_SaveBtnID, 'dobutton', 'IA.POST', 'create');
                }

                $this->setButtonDetails($values, Editor_SaveBtnID, 'draftbutton', 'IA.DRAFT', 'draftcreate');

                $this->setButtonDetails($values, Editor_CancelBtnID, 'cancelbutton', 'IA.CANCEL', 'cancel', false);

                if ($this->CanSave() && $this->dt == BUILD_KIT) {
                    $this->createMoreActionEntry(
                        $values, Editor_SaveAndNewBtnID, 'saveandnewbutton', 'IA.POST_AND_NEW', 'create', true, null, true,
                        false, array('after' => 1)
                    );

                    $this->createMoreActionEntry(
                        $values, Editor_SaveBtnID, 'scontinuebutton', 'IA.DRAFT_AND_CONTINUE', 'savecontinue'
                    );
                }

                break;


            case Editor_ShowEditState:

                if ($this->CanSave()) {
                    $this->setButtonDetails($values, Editor_SaveBtnID, 'dobutton', 'IA.POST', 'save');
                }

                if ($draftMode) {
                    $this->setButtonDetails($values, Editor_SaveBtnID, 'draftbutton', 'IA.DRAFT', 'draftsave');
                }

                $this->setButtonDetails($values, Editor_CancelBtnID, 'cancelbutton', 'IA.CANCEL', 'cancel', false);

                break;

            case Editor_ShowViewState:
                
                if ($draftMode) {
                    $this->setButtonDetails(
                        $values, 'editbuttid', 'editbutton', 'IA.EDIT', 'edit', false, 'window.editor.doEdit()', false
                    );
                }

                $this->setButtonDetails($values, Editor_CancelBtnID, 'cancelbutton', 'IA.DONE', 'cancel', false);

                if ($this->CanPrint()) {
                    //$this->setButtonDetails($values, 'saveandprintbuttid', 'deliverbutton', 'Print To...', 'deliver', false, "showDeliverPageNew(true, data)", false);
                    $this->createMoreActionEntry(
                        $values, 'saveandprintbuttid', 'deliverbutton', 'IA.PRINT_TO', 'deliver', false,
                        "showDeliverPageNew(true, data)", false, false
                    );
                }

                break;
        }


        return $values;
    }

    /**
     * @param array $_layout
     * @param array $obj
     *
     * @return int
     */
    function FigureOutNumOfRows($_layout, &$obj=null)
    {
        if ( $_layout['path'] == 'ENTRIES' ) {
            return 1;
        } else {
            return parent::FigureOutNumOfRows($_layout, $obj);
        }
    }
    

    /**
     * @param array $field
     *
     * @return bool
     */
    function showExpandedConvertedFrom(/** @noinspection PhpUnusedParameterInspection */ $field)
    {
        return true;
    }

    /**
     * @param string $ownerobject
     * @param string $type
     *
     * @return array
     */
    function GetCustomComponents($ownerobject, $type="all")
    {
        $ret_fields = FormEditor::GetCustomComponents($ownerobject, "customfield");

        // TBD :: Let us do a migration for this.
        // After migrating to the new editor, the 'LINE ITEMS' become part of the Header page
        // and the line level custom fields become part of the details window shade section
        // This piece of code is for backward compatibility
        foreach ( $ret_fields as $indx => $value ) {
            if (isl_strtoupper(isl_trim($value['PAGE'])) === 'LINE ITEMS'
                || isl_trim($value['PAGE']) === 'IA.LINE_ITEMS'
                || isl_strtoupper(isl_trim($value['PAGE'])) === 'HEADER'
                || isl_trim($value['PAGE']) === 'IA.HEADER'
            ) {
                if ( $ownerobject === 'stkitdocument' ) {
                    $ret_fields[$indx]['PAGE'] = GT($this->textMap,'IA.TRANSACTION');
                } else if ( $ownerobject === 'stkitdocumententry' ) {
                    $ret_fields[$indx]['PAGE'] = GT($this->textMap,'IA.DETAILS');
                }
            }
        }

        return $ret_fields;
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function prepareObjectForCreate(&$obj)
    {

        parent::prepareObjectForCreate($obj);

        $list_op = GetOperationId($this->mod . '/lists/stkitdocument');
        
        $_sess = Session::getKey();
        $this->done = 'lister.phtml?.op=' . $list_op . '&.dt=' . $this->dt . '&.sess=' . $_sess;

        return true;

    }

    /**
     *  setting done parameter
     */
    protected function SetDoneParam()
    {
        $list_op = GetOperationId($this->mod . '/lists/stkitdocument');
        
        $_sess = Session::getKey();
        $this->done = 'lister.phtml?.op=' . $list_op . '&.dt=' . $this->dt . '&.sess=' . $_sess;
    }
    
    /**
     * @return int
     */
    protected function getOperationIdForSaveContinue()
    {
        return GetOperationId($this->mod . '/lists/stkitdocument/edit');
    }

    /**
     * @param array $_params
     */
    protected function buildDynamicMetadata(&$_params)
    {
        if ( !util_isPlatformDisabled() ) {
            $customEntity = $this->getEntityMgr()->GetCustomComponentsEntity();

            $entityName = isl_strtoupper($customEntity);
            $this->platformObject = Pt_StandardUtil::getPlatformObject($entityName);
            if ( isset($this->platformObject) && $this->platformObject ) {
                $this->considerPlatform = true;
                $this->platformPage = Pt_StandardUtil::getPlatformObjectPage($this->platformObject, $this->verb);
            }
        }
        
        parent::buildDynamicMetadata($_params);
    }

    /**
     * We override to not cleanup our UI grids line items
     *
     * @param EditorGrid    $grid
     * @param EntityManager $entityMgr
     * @param array         $_obj
     */

    protected function innerCleanupLineItems($grid, $entityMgr, &$_obj)
    {
        $gridPath = $grid->getProperty('path');
        if ($gridPath === 'SKTRACKINGGRID' || $gridPath === 'SKCOMPONENTGRID' || $gridPath === 'SKCOMPONENTTRACKINGGRID') {
            return;
        }

        parent::innerCleanupLineItems($grid, $entityMgr,$_obj);
    }

    /**
     * Override the base parent method as we don't need that behavior
     *
     * @param array $obj
     *
     */
    protected function ProcessTrackingEntries(/* @noinspection PhpUnusedParameterInspection */ &$obj)
    {
        //Base class ProcessTrackingEntries is filtering the TRACKINGENTRIES in the ENTRIES which we don't need.
        //So we purposely override to not do anything here
    }

    /**
     * These are used for links to tracking grids in build kits transactions.
     *
     * @return array|string[]
     */
    protected function getFormTokens() : array
    {
        $this->textTokens = array_merge($this->textTokens, [
            'IA.SERIAL',
            'IA.SERIAL_EXPIRATION',
            'IA.LOT',
            'IA.LOT_EXPIRATION',
            'IA.BIN',
            'IA.SERIAL_LOT',
            'IA.SERIAL_LOT_EXPIRATION',
            'IA.SERIAL_BIN',
            'IA.SERIAL_BIN_EXPIRATION',
            'IA.LOT_BIN',
            'IA.LOT_BIN_EXPIRATION',
            'IA.SERIAL_LOT_BIN',
            'IA.SERIAL_LOT_BIN_EXPIRATION',
            'IA.SK_TOTAL_QTY_GREATER_THAN_ENTRY_QTY',
            'IA.SK_TRACK_QTY_GREATER_THAN_ENTRY_QTY',
            'IA.OE_TRACK_QTY_GREATER_THAN_AVAILABLE_QTY', // Yes, OE prefix since it's the same msg in this case
        ]);
        return parent::getFormTokens();
    }
}


