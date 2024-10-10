<?php

/**
 * =============================================================================
 *
 * FILE:        DocumentEditor.cls
 * AUTHOR:        Unknown, Sudeendra Ramesh
 * DESCRIPTION:    Editor for all documents in Inventory module
 *
 * (C)2000,2010 Intacct Corporation, All Rights Reserved
 *
 * Intacct Corporation Proprietary Information.
 * This document contains trade secret data that belongs to Intacct
 * corporation and is protected by the copyright laws. Information herein
 * may not be used, copied or disclosed in whole or part without prior
 * written consent from Intacct Corporation.
 * =============================================================================
 */
class InvDocumentFormEditor extends DocumentFormEditor
{

    const PermissionKeys_Create = ['inv/lists/invdocument/create','inv/activities/invdocument/create'] ;
    const PermissionKeys_Edit = ['inv/lists/invdocument/edit'] ;
    const PermissionKeys_View = ['inv/lists/invdocument/view'] ;

    /**
     * @param string[] $_params
     */
    public function __construct($_params)
    {
        parent::__construct($_params);
    }

    /**
     * @param array $obj
     * @param array $docparmrec
     */
    protected function mediateDataAndMetadata_Entries(&$obj, $docparmrec)
    {
        parent::mediateDataAndMetadata_Entries($obj, $docparmrec);

        if ($this->state != 'showview' && $this->dt != '') {

            $docpar = $this->GetBaseDocPar();

            $outDocument = (
                !$obj['ADJDOCHDRID'] 
                && $docpar['IN_OUT'] == 'Decrease' 
                && $docpar['UPDATES_INV'] != 'No' 
                && $docpar['UPDATES_INV'] != 'Value'
            );

            $view = $this->getView();

            if ($outDocument) {
                $entriesViewArr = array();
                $view->findComponents(array('path' => 'ENTRIES'), EditorComponentFactory::TYPE_GRID, $entriesViewArr);
                $entriesView = $entriesViewArr[0];

                $entriesView->findAndSetProperty(
                    array('path' => 'UIPRICE'), array('required' => false, 'disabled' => true)
                );
                $entriesView->findAndSetProperty(array('path' => 'UIVALUE'), array('disabled' => true));
            }
            //for some reason the precision value from .ent is coming as string is not working
            // so this is work around until it is fixed
            $entriesViewArr = array();
            $view->findComponents(array('path' => 'FLOAT_TRACKINGENTRIES_GRID'), EditorComponentFactory::TYPE_GRID, $entriesViewArr);
            if (is_array($entriesViewArr) && count($entriesViewArr)>0){
                $entriesViewArr[0]->findAndSetProperty(array('path' => 'TRACK_QUANTITY'), array('precision' => 10));
            }
        }
    }

    /**
     * @param array   $obj
     *
     * @throws Exception
     */
    protected function mediateDataAndMetadata_Header(&$obj)
    {
        parent::mediateDataAndMetadata_Header($obj);

        $view = $this->getView();
        $docpar = $this->GetBaseDocPar();

        $suppliesIssue = ItemManager::isSuppliesInventoryEnabled() &&
                        (($obj['DOCPARID'] ?? '') === PODocumentManager::SUPPLIESISSUEDOCTYPE);
        if ($suppliesIssue) {
            $createdFromField = array();
            $view->findComponents(array('path' => 'CREATEDFROM'), EditorComponentFactory::TYPE_FIELD, $createdFromField);
            if (isset($createdFromField[0])) {
                $createdFromField[0]->setProperty('hidden', true);   // confusing ("but I created this from multiple supply requests!")
            }
        }

        if (empty($obj['CREATEDFROM'])) {
            $adjDocHdr = array();
            $view->findComponents(array('path' => 'ADJDOCHDRID'), EditorComponentFactory::TYPE_FIELD, $adjDocHdr);
            if (isset($adjDocHdr[0]) && $docpar['UPDATES_INV'] != 'No') {
                $adjDocHdr[0]->setProperty('hidden', $suppliesIssue);   // shown, unless supplies

                if ($this->state != $this->kShowNewState) {
                    $adjDocHdr[0]->setProperty('readonly', true);
                }
                $type = $adjDocHdr[0]->getProperty('type');

                $allowedTDs = array('Quantity and Value');
                if ($docpar['UPDATES_INV'] == 'Value') {
                    $allowedTDs[] = 'Value';
                }

                $restrict = array(
                    'pickField' => 'UPDATES_INV',
                    'operand' => 'IN',
                    'value' => $allowedTDs
                );

                $type['restrict'][] = $restrict;

                $adjDocHdr[0]->setProperty('type', $type);
            }

            if ($obj['ADJDOCHDRID']) {
                $matches = array();
                $view->findComponents(array('path' => 'ENTRIES'), EditorComponentFactory::TYPE_GRID, $matches);
                if ($matches) {
                    $matches[0]->setProperty('noNewRows', true);
                    $matches[0]->setProperty('hasFixedNumOfRows', true);
                }
            }
        }
    }
    
    /**
     * @param array $obj
     * @param array $docparmrec
     *
     * @return bool
     */
    protected function showVatFieldsForAvaTaxEngine($obj, $docparmrec)
    {
        // Never show VAT fields for Inventory TDs
        return false;
    }

    /**
     * @return array
     */
    protected function getItemPickRestrictParams()
    {
        $restrictItemTypes = parent::getItemPickRestrictParams();
        $restrictItemTypes[] = 'NS';
        $restrictItemTypes[] = 'NP';
        $restrictItemTypes[] = 'NI';
        return $restrictItemTypes;
    }

    /**
     * @param array  $obj
     * @param string $indx
     * @param array  $history
     * @param int   $totalLineCountUNUSED
     *
     * @return bool
     */
    protected function setHistoryValuesByRow(&$obj, $indx, $history, $totalLineCountUNUSED)
    {
        if ($this->dt == BUILD_KIT || $this->dt == DIS_KIT) {
            $state = $history['DOCSTATE'];
            $docid = '';
            if ($history['DOCUMENTID']) {
                list($docid) = explode('-', $history['DOCUMENTID']);
            }
            if ($docid == BUILD_KIT && $state == 'Converted') {
                $obj['HISTORY'][$indx]['DOCSTATE'] = 'Disassembled';
            } elseif ($docid == BUILD_KIT && $state == 'Pending') {
                $obj['HISTORY'][$indx]['DOCSTATE'] = 'Built';
            } elseif ($docid == DIS_KIT && $state == 'Pending') {
                $obj['HISTORY'][$indx]['DOCSTATE'] = 'Disassembled';
            }
        }
        return true;
    }

    /**
     * @param array   $obj
     *
     * @return bool
     *
     * @throws Exception
     */
    protected function transformBizObjectToView(&$obj)
    {
        $ok = parent::transformBizObjectToView($obj);

        if ( $ok) {
            if (isset($obj['ENTRIES']) && is_array($obj['ENTRIES'])) {
                $adjDocHdrKey = '';
                foreach ($obj['ENTRIES'] as &$entry) {
                    // TODO this looks odd , its picking only the last entry's adjdochdrkey and ignoring others ???
                    $adjDocHdrKey = $entry['ADJDOCHDRKEY'];
                }
                unset($entry);

                if (!empty($adjDocHdrKey)) {
                    $docMgr = Globals::$g->gManagerFactory->getManager('document');
                    $params = array(
                        'selects' => array('DOCID'),
                        'filters' => array(
                            array(
                                array('RECORDNO', '=', $adjDocHdrKey),
                            )
                        ),
                    );

                    $recs = $docMgr->GetList($params);

                    $obj['ADJDOCHDRID'] = $recs[0]['DOCID'];
                }
            }
        }

        return $ok;
    }
    
/**
     * @param array $docpar
     * @param bool $autofill
     *
     * @return bool
     */
    protected function ShowGLPostingDate($docpar, &$autofill=false)
    {
        $flag = ( $docpar['DOCID'] == InvDocumentManager::LANDEDCOSTDOCTYPE ||
                  $docpar['DOCID'] == InvDocumentManager::LANDEDCOSTESTDOCTYPE ||
                  $docpar['DOCID'] == InvDocumentManager::LANDEDCOSTESTREVDOCTYPE);
        return $flag;
    }
    
    
    /**
     * @return bool
     */
    protected function IsDraftMode()
    {
        //If supplies issue/return txns, we don't allow draft to be posted
        $docpar = $this->GetBaseDocPar();
        if ($docpar['DOCID'] === PODocumentManager::SUPPLIESISSUEDOCTYPE
            || $docpar['DOCID'] === PODocumentManager::SUPPLIESRETURNDOCTYPE) {
            return false;
        }

        global $kINVid;
        $isDraftMode = (GetPreferenceForProperty($kINVid, 'DRAFTMODE') == 'F') ? false : true;
        return $isDraftMode;
    }

    /**
     * @return array
     * @throws Exception
     */
    protected function getEditorGlobals()
    {
        $vars = parent::getEditorGlobals();
        $vars['draftmode']   = $this->IsDraftMode();
        $vars['supplies_op'] = GetOperationId( 'inv/lists/invsupplies' );
        return $vars;
    }

    /**
     * Map the ajax action to a PHP function
     *
     * @param string $cmd the Ajax action requested
     *
     * @return bool false if command not found
     */
    protected function runAjax($cmd)
    {
        $ok = true;

        switch ( $cmd ) {
            case 'calculateSubTotals':
                $this->ajaxCalculateSubTotals();
                break;
            default:
                $ok = parent::runAjax($cmd);
                break;
        }

        return $ok;
    }

    /**
     * @param array $_params
     * Override to check permission
     * @return bool
     */
    protected function ProcessViewAction(&$_params)
    {
        if(!hasPermissionForms(self::PermissionKeys_View)) {
            return false;
        }
        return parent::ProcessViewAction($_params);
    }

    /**
     * @param array $_params
     * Override to check permission
     * @return bool
     */
    protected function ProcessEditAction(&$_params)
    {
        if(!hasPermissionForms(self::PermissionKeys_Edit)) {
            return false;
        }
        return parent::ProcessEditAction($_params);
    }

    /**
     * @param array $_params
     * Override to check permission
     * @return bool
     */
    protected function ProcessEditNewAction(&$_params)
    {
        if(!hasPermissionForms(self::PermissionKeys_Create)) {
            return false;
        }
        return parent::ProcessEditNewAction($_params);
    }

    /**
     *      Override of process Copy Convert, used during conversions....
     *
     * @param string $copy
     * @param array  $old
     *
     * @return bool
     */
    protected function processCopyConvert($copy, &$old)
    {
        $ok = true;
        if (ItemManager::isSuppliesInventoryEnabled() && ($copy === 'Update')) {
            $suppliesManager = Globals::$g->gManagerFactory->getManager('invsupplies');
            $ok = $suppliesManager->processCopyConvert($copy, $old, Request::$r->_suppliesaction, Request::$r->_records);
        }
        return $ok && parent::processCopyConvert($copy, $old);
    }


    /**
     * @return bool
     */
    protected function canPrintPickList()
    {
        $docpar         = $this->GetBaseDocPar();
        $suppliesIssue  = ItemManager::isSuppliesInventoryEnabled() &&
            (($docpar['DOCID'] ?? '') === PODocumentManager::SUPPLIESISSUEDOCTYPE);

        if ($suppliesIssue) {
            return false;
        }
        return parent::canPrintPickList();
    }


    /**
     * @param string $state
     *
     * @return string[]
     * @throws Exception
     */
    public function getStandardButtons($state)
    {
        $buttons        = parent::getStandardButtons($state);
        $docpar         = $this->GetBaseDocPar();
        $suppliesIssue  = ItemManager::isSuppliesInventoryEnabled() &&
                                (($docpar['DOCID'] ?? '') === PODocumentManager::SUPPLIESISSUEDOCTYPE);

        if ($suppliesIssue && ($this->do != 'shownew') && ($this->do != 'create')) {
            $args = array(
                'recurOp' => GetOperationId('inv/lists/invsupplies' ),
                'dt'      => $this->dt,
                'mod'     => $this->mod,
            );
            $this->setButtonDetails($buttons, 'suppicklist', 'suppicklist', 'IA.PRINT_PICK_LIST',
                '', true, 'SuppliesPickListReport()', false, false, $args);
        }
        return $buttons;
    }


    /**
     * If a PO txn form is a shown as a popup and it's about to close, maybe we need to refresh the underlying screen.
     *
     * @param string $key
     * @param array  $obj
     *
     * @return string
     */
    protected function getPopupCloseJS($key, $obj = [])
    {
        //Ask the parent for the close popup func to return
        $func = parent::getPopupCloseJS($key, $obj);

        // maybe someday this will work for everyone....
        if (ItemManager::isSuppliesInventoryEnabled()) {
            // key and obj refer to the POPUP, not the underlying form.
            // so invoke the refreshTable function if it exists....
            // popupClosedAfterEdit() is in the UNDERLYING js, in supplies case invsupplies.js (not documentformeditor_new)
            $func .= ' if (typeof window.parent.popupClosedAfterEdit === "function") { window.parent.popupClosedAfterEdit(); } ';
        }
        return $func;
    }


}
