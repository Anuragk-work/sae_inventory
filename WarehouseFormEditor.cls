<?php

/**
 * Intacct Corporation Proprietary Information.
 * This document contains trade secret data that belongs to Intacct
 * corporation and is protected by the copyright laws. Information herein
 * may not be used, copied or disclosed in whole or part without prior
 * written consent from Intacct Corporation.
 *
 * @filesource WarehouseFormEditor.cls
 * @author     Sandeep Pasunuri <spasunuri@intacct.com>
 * @copyright  2000-2009 Intacct Corporation
 */

/**
 * Class WarehouseFormEditor
 */
class WarehouseFormEditor extends FormEditor
{
    /**
     * Warehouse specific tokens
     * @var string[]
     */
    private $warehouseTokens = ['IA.DUPLICATE','IA.PRINT_TO','IA.CANCEL','IA.EDIT','IA.DONE'];

    const PermissionKeys_Create = ['inv/lists/warehouse/create','so/lists/warehouse/create','po/lists/warehouse/create'] ;
    const PermissionKeys_Edit = ['inv/lists/warehouse/edit','so/lists/warehouse/edit','po/lists/warehouse/edit'] ;
    const PermissionKeys_View = ['inv/lists/warehouse/view','so/lists/warehouse/view','po/lists/warehouse/view'] ;

    /**
     * @param array $_params
     */
    function __construct($_params = array())
    {
        $this->additionalTokens = array_merge($this->additionalTokens, $this->warehouseTokens);
        parent::__construct($_params);
    }

    /**
     * @param string $state
     *
     * @return array
     */
    public function getStandardButtons($state)
    {
        $values = [];

        switch ($state) {
            case Template_EditWarningState:
            case Editor_ShowEditState:
                if( $this->CanSave() ) {
                    $this->setButtonDetails($values, Editor_SaveBtnID, 'dobutton', $this->getLabelForSaveButton(), 'save', true, 'okToSave(data)');
                }
                if ($this->CanDuplicate()) {
                    $this->setButtonDetails($values, 'savebutton', 'copybutton', 'IA.DUPLICATE', 'copy', true, 'window.editor.prepareForDuplicate()', true, true);
                }
                if ($this->CanShowAuditTrail()) {
                    $this->configureAuditTrailButton($values);
                }
                if( $this->CanPrint() ) {
                    $this->createMoreActionEntry($values, 'saveandprintbuttid', 'deliverbutton', 'IA.PRINT_TO', 'deliver', false, "showDeliverPageNew(true, data)", false, false);
                }
                $this->setButtonDetails($values, Editor_CancelBtnID, 'cancelbutton', 'IA.CANCEL', 'cancel', false, 'okToCancel(data)');
                $this->addHelpButton($values);
                break;

            case Editor_ShowViewState:
                if ($this->CanShowAuditTrail()) {
                    $this->configureAuditTrailButton($values);
                }
                if( $this->CanPrint() ) {
                    $this->createMoreActionEntry($values, 'saveandprintbuttid', 'deliverbutton', 'IA.PRINT_TO', 'deliver', false, "showDeliverPageNew(true, data)", false, false);
                }
                if($this->CanEdit()) {
                    $this->setButtonDetails($values, 'editbuttid', 'editbutton', 'IA.EDIT', 'edit', false, 'window.editor.doEdit()', false);
                }
                if ($this->CanDuplicate()) {
                    $this->setButtonDetails($values, 'savebutton', 'copybutton', 'IA.DUPLICATE', 'copy', true, 'window.editor.prepareForDuplicate()', true, true);
                }
                $this->setButtonDetails($values, Editor_CancelBtnID, 'cancelbutton', 'IA.DONE', 'cancel', false);
                $this->addHelpButton($values);
                break;

            default:
                $values = parent::getStandardButtons($state);
        }
        return $values;
    }


    /**
     * Removing unwanted values while duplicating record
     *
     * @param array $obj Object details
     *
     * @access protected
     * @return bool True or False based on the status of the call
     */
    protected function prepareObjectForCopyNew(&$obj)
    {
        parent::prepareObjectForCopyNew($obj);

        // mostly get rid of the aisle/row/bin stuff, but just to be clean.....
        $unsetThese = [ 'WAREHOUSEID', 'NAME', 'WHENCREATED', 'WHENMODIFIED', 'CREATEDBY', 'MODIFIEDBY',
                        'AISLE_INFO', 'ROW_INFO', 'BIN_INFO_CLASSIC', 'BIN_INFO' ];
        foreach ($unsetThese as $field) {
            unset($obj[$field]);
        }
        return true;
    }


    /**
     *      hide a list of sections or grids or fields
     *
     * @param string    $type       EditorComponentFactory::TYPE_GRID or EditorComponentFactory::TYPE_SECTION or ...
     * @param string[]  $list       The array of ids or paths to hide
     */
    private function hide($type, $list)
    {
        $view = $this->getView();
        $fieldType = ($type == EditorComponentFactory::TYPE_SECTION) ? 'id' : 'path';
        foreach ($list as $field) {
            $obj = [];
            $view->findComponents([$fieldType => $field], $type, $obj);
            if (isset($obj[0])) {
                $obj[0]->setProperty('hidden', true);
            }
        }
    }


    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function mediateDataAndMetadata(&$obj)
    {
        $kINVid = Globals::$g->kINVid;

        GetModulePreferences($kINVid, $prefs);
        $view   = $this->getView();
        $binMgr = Globals::$g->gManagerFactory->getManager('bin');
        $state  = $this->getState();

        // if bins are on, and advanced bins are on, then hide aisle and row
        if ($prefs['ENABLEBIN'] == 'T') {
            if (BinManager::areAdvanedBinsOn()) {
                $this->hide(EditorComponentFactory::TYPE_GRID,    ['AISLE_INFO', 'ROW_INFO']);
                $this->hide(EditorComponentFactory::TYPE_SECTION, ['aisleInfo', 'rowInfo', 'binInfoClassic']);

                // On 'Save and New' we get called with 'new' state, but the bins are still filled in from the SAVE...
                if (($state == $this->kShowNewState) && (isset($obj['BIN_INFO']))) {
                    foreach ($obj['BIN_INFO'] as $index => $row) {
                        $changeMade = false;
                        foreach ($row as $fieldName => $fieldValue) {
                            if (substr($fieldName, 0, 1) != '_') {
                                // fields like __dummy and _isNewField are ok, nothing else is....
                                unset($row[$fieldName]);
                                $changeMade = true;
                            }
                        }
                        if ($changeMade) {
                            $obj['BIN_INFO'][$index] = $row;
                        }
                    }
                    $obj['NAME'] = '';
                }

                if (($obj['WAREHOUSEID'] ?? '') != '') {
                    $inUse = $binMgr->whichBinsAreInUse($obj['WAREHOUSEID']);
                    foreach ($obj['BIN_INFO'] as $index => $row) {
                        if (isset($inUse[$row['BINKEY']])) {
                            $obj['BIN_INFO'][$index]['NO_DELETE'] = 'T';    // no, you cannot delete it.
                        }
                    }
                }

                // for now.  do we NEED this button?
                $this->hide(EditorComponentFactory::TYPE_BUTTONS, ['bulkAction']);
            } else {
                // hide the non-advanced columns
                $this->hide(EditorComponentFactory::TYPE_SECTION, ['binInfo']);
                $this->hide(EditorComponentFactory::TYPE_GRID_COLUMN, ['ZONEID', 'AISLEID', 'ROWID', 'FACEID']);
                // can't have two sections with the same name in the form xml....
                //$obj['BIN_INFO_CLASSIC'] = $obj['BIN_INFO'];
                foreach ($obj['AISLE_INFO'] as $index => $row) {
                    $obj['AISLE_INFO'][$index]['AISLEIDCLASSIC'] = $row['AISLEID'] ?? '';   // to avoid name confusion.
                }
            }
        } else {
            // if bins are off, hide everything to do with bins
            $this->hide(EditorComponentFactory::TYPE_GRID,    ['AISLE_INFO', 'ROW_INFO', 'BIN_INFO']);
            $this->hide(EditorComponentFactory::TYPE_SECTION, ['aisleInfo', 'rowInfo', 'binInfo', 'binInfoClassic']);
        }

        $matches = array();
        $view->findComponents(array('path' => 'LOC.LOCATIONID'), EditorComponentFactory::TYPE_FIELD, $matches);
        if (isset($matches[0])) {
            $matches[0]->setProperty('required', IsMultiEntityCompany());
        }

        $replenishment = (($prefs['AI_REPLENISHMENTS'] == 'T') && ($prefs['ADVANCED_INVENTORY'] == 'T'));
        if ($replenishment) {
            // if never set, default to ON
            if ((($obj['ENABLE_REPLENISHMENT'] ?? null) == null) || ($obj['ENABLE_REPLENISHMENT'] == '')) {
                $obj['ENABLE_REPLENISHMENT'] = 'T';
            }
        } else {
            $this->hide(EditorComponentFactory::TYPE_FIELD,  ['ENABLE_REPLENISHMENT']);
        }

        //If the inv/OE config's disallow negative inv checkbox is NOT checked or supplies inventory
        //checkbox is checked, we will hide the warehouse neg inv overridden checkbox
        if ($prefs['ENABLESUPPLIESINVENTORY'] === 'T' || $prefs['DISALLOW_NEGINV'] != 'T') {
            $this->hide(EditorComponentFactory::TYPE_FIELD, ['ENABLENEGATIVEINV']);
        } else {
            // default to 'false' if value for ENABLENEGATIVEINV is not set or empty
            if ( ! isset($obj['ENABLENEGATIVEINV']) || empty($obj['ENABLENEGATIVEINV']) ) {
                $obj['ENABLENEGATIVEINV'] = 'false';
            }
        }
        return true;
    }




    /**
     * getEntityData
     *    helper function to get data from entity manager and format the data for display
     *
     * @param string        $entity   entity or object
     * @param string        $objId    entityid or objectid
     * @param string        $doctype
     * @param string[]|null $fields
     *
     * @return array|false the formatted result set
     */
    protected function getEntityData($entity, $objId, $doctype='', $fields=null)
    {
        // are we in CLASSIC mode?
        if (BinManager::areAdvanedBinsOn() == false) {
            $warehouseManager = $this->GetManager('warehouse');
            $warehouseManager->allowClassicOwnedObjects(true);
        }

        return parent::getEntityData($entity, $objId, $doctype, $fields);
    }



    /**
     * @param array  $obj
     *
     * @return bool
     */
    protected function prepareObjectForSubmit(&$obj)
    {
        // If we care coming from the UI for the Classic version of Bins, we have some fixin' to do....
        // for Advanced Bins, make sure the Window ID is assigned
        if (BinManager::areAdvanedBinsOn()) {
            foreach (($obj['BIN_INFO'] ?? []) as $index => $row) {
                $obj['BIN_INFO'][$index]['WAREHOUSEID'] = $obj['LOCATIONID']; // might not have been assigned.
            }
        } else {
            $warehouseManager = $this->GetManager('warehouse');
            $warehouseManager->allowClassicOwnedObjects(true);

            if (isset($obj['BIN_INFO_CLASSIC'])) {
                foreach (($obj['BIN_INFO_CLASSIC'] ?? []) as $index => $row) {
                    $obj['BIN_INFO_CLASSIC'][$index]['BINID'] = $row['BINIDCLASSIC'] ?? $row['BINID']; // take the classic version
                }
            }

            if (isset($obj['AISLE_INFO'])) {
                foreach (($obj['AISLE_INFO'] ?? []) as $index => $row) {
                    $obj['AISLE_INFO'][$index]['AISLEID'] = $row['AISLEIDCLASSIC'] ?? $row['AISLEID']; // take the classic version
                }
            }
        }
        return true;
    }


    /**
     * Hook for subclasses to prepare the object during a save action
     * At the time of the call the object is in business form
     *
     * @param array &$obj  the object (in and out)
     *
     * @return bool
     */
    protected function prepareObjectForSave(&$obj)
    {
        return $this->prepareObjectForSubmit($obj);
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
        return $this->prepareObjectForSubmit($obj);
    }



    /**
     * @return array
     */
    protected function getJavaScriptFileNames()
    {
        $jsfiles[] = "../resources/js/warehouse.js";
        return $jsfiles;
    }

    /**
     * @return array
     */
    protected function getCssFileNames()
    {
        $cssfiles[] = "../resources/css/warehouse.css";
        return $cssfiles;
    }

    /**
     * @param EntityManager $entityMgr
     * @param array         $obj
     * @param bool          $isCopyNew
     */
    protected function resetKeys($entityMgr, &$obj, $isCopyNew = false)
    {
        $tempObj = $obj;

        parent::resetKeys($entityMgr, $obj, $isCopyNew);

        // We will reset the VID and AUTOINCREMENT from the ownedobjects too
        $ownedObjects = $entityMgr->GetOwnedObjects();
        foreach ($ownedObjects as $ownedObject) {
            $obj[$ownedObject['path']] = $tempObj[$ownedObject['path']];

            $ownedMgr = Globals::$g->gManagerFactory->getManager($ownedObject['entity']);
            $relationFld = 'LOCATIONID';
            $autoIncrement = $ownedMgr->getAutoIncrementFieldName();

            foreach ( $obj[$ownedObject['path']] as &$object) {
                EntityManager::SetByPath($object, $relationFld, '');
                EntityManager::SetByPath($object, $autoIncrement, '');
            }
        }
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
        // $response = null;
        switch ($cmd) {
            case 'getFields':
                $response = $this->ajaxGetFields( Request::$r->{'from'}, Request::$r->{'id'} );
                break;

            case 'doesBinExist':
                $response = $this->ajaxDoesBinExist( Request::$r->{'id'}, Request::$r->{'recordno'} );
                break;

            default:
                return parent::runAjax($cmd);   // doesn't return stuff to output, only true/false
        }

        if ($response !== null) {
            echo json_encode($response);
        }

        return $ok;
    }


    /**
     *      Does the given bin id exist anywhere?  If it does, and it is NOT the given record #,
     *  then return an error message for display.  (on new records in the UI, the recordNo will be 0)
     *
     * @param string    $id         bin id
     * @param int       $recordNo   record number or zero
     *
     * @return array                the table of values
     */
    protected function ajaxDoesBinExist($id, $recordNo)
    {
        $id     = trim($id);
        $exists = 'F';
        $msg    = '';
        $binMgr = Globals::$g->gManagerFactory->getManager('bin');
        $res = $binMgr->get($id);
        if (($res !== false) && isset($res['RECORDNO']) && ((int)$res['RECORDNO'] != (int)$recordNo)) {
            $exists = 'T';
            $msg    = sprintf(_('Bin “%1$s” already exists in warehouse %2$s. Rename the Bin ID to proceed. Bin IDs must be unique to the company, not just within a warehouse.'), $id, $res['WAREHOUSEID']);
        }
        return ['EXISTS' => $exists, 'MESSAGE' => $msg];
    }


    /**
     * @param string    $from   is this aisle?  row?  bin?
     * @param string    $id     the key to look up
     *
     * @return array  the results
     */
    protected function ajaxGetFields($from, $id)
    {
        if ($from == 'AISLE') {
            $entity = 'aisle';
        }else if ($from == 'BIN') {
            $entity = 'bin';
        }else if ($from == 'ROW') {
            $entity = 'icrow';
        } else {
            throw new Exception("[Code Bug] bad ajax call: $from");
        }

        $res = [];
        if (($id ?? '') != '') {
            $aislerowbinMgr = Globals::$g->gManagerFactory->getManager($entity);
            $res = $aislerowbinMgr->get($id);
            if ($res === false) {
                $res = [];
            } else if ($from == 'AISLE') {
                $res['AISLEIDCLASSIC'] = $res['AISLEID'] ?? '';   // to avoid name confusion.
            }
        }
        return ['FIELDS' => $res];
    }


    /**
     *      when printing to PDF, we don't want to print the hidden sections.  In Bin Advanced Mode, then,
     *  we want to REMOVE the 'Classic Mode' sections.  And vice versa.
     *
     * The 'data' includes the entire UI tree, including stuff we don't want.  It is recursive and nested DEEP....
     *
     * @param array       $data                   A section of the params to examine
     * @param string[]    $idsToRemove            The names of the IDs you want to remove.
     *
     * @return  bool                             TRUE means remove the subsection, FALSE means keep it.
     */
    private function removeXSLSectionsWeDontWant(&$data, $idsToRemove)
    {
        if (is_array($data)) {
            foreach ($data as $key => &$value) {

                // the ids we're looking for are ALWAYS after a subsection, and as part of entry 0....
                if ($key === 'subsection') {
                    $remove = $this->removeXSLSectionsWeDontWant($value[0], $idsToRemove);
                    if ($remove) {
                        unset($data['subsection'][0]);  // remove the whole sub-tree
                    }
                }

                if (($key === 'id') && (in_array($value,$idsToRemove))) {
                    return true;    // ask caller to remove us
                } else if (is_array($value)) {
                    $remove = $this->removeXSLSectionsWeDontWant($value, $idsToRemove); // Recurse down the tree
                    if ($remove) {
                        return true;
                    }
                }
            }
        }
        return false;
    }


    /**
     * Delivers current record in online as well as offline mode
     *
     * @param array         $_params  the editor params
     * @param bool          $offline  true if we are printing offline else false
     * @param string|false  $out      output when Request::$r->_deliverymethod pdf (the defautl)
     *
     * @return bool
     */
    public function Editor_Deliver(&$_params, $offline, &$out)
    {
        $method = Request::$r->_deliverymethod;
        if( ! $method ) {
            $method = 'pdf';
        }

        $localParams = $_params;
        if ($method == 'pdf') {
            // edit out the sections that shouldn't show.
            if (BinManager::areAdvanedBinsOn()) {
                $removeThese = ['aisleInfo', 'rowInfo', 'binInfoClassic'];
            } else {
                $removeThese = ['binInfo'];
            }
            $this->removeXSLSectionsWeDontWant($localParams['view']['child'][0]['pages'], $removeThese);
        }

        $ok = parent::Editor_Deliver($localParams, $offline, $out);

        return $ok;
    }

    /**
     * @return string[]
     */
    protected function getFormTokens() : array
    {
        $this->textTokens[] = 'IA.CONFIRM_CLEAR_BIN_ID';
        $this->textTokens[] = 'IA.ALERT_MISSING_BIN_ID';
        return parent::getFormTokens();
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
        $warehouseId = isl_htmlspecialchars_decode(Request::$r->{Globals::$g->kId});
        Request::$r->{Globals::$g->kId} = $warehouseId;
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
}

