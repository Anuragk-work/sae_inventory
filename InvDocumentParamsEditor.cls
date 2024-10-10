<?php

/**
 * Adds the functionality specific for the Inventory Transaction Definition.
 *
 * @author    Samvel Mirijanyan <smirijanyan@intacct.com>
 * @copyright 2000-2015 Intacct Corporation All, Rights Reserved
 */

/**
 * Class InvDocumentParamsEditor
 */
class InvDocumentParamsEditor extends DocumentParamsEditor
{
    /**
     * @param array $_params
     */
    public function __construct($_params = array())
    {
        I18N::addToken('IA.NO_DELETE');
        I18N::addToken('IA.BEFORE_PRINTING');
        I18N::addToken('IA.DELETE_IN_DRAFT_ONLY');
        I18N::addToken('IA.ALL');
        parent::__construct($_params);
    }

    /**
     * Overrides the method. Calls the method in the parent class implementing
     * the common data adjustments and dose all the specifics for the
     * Inventory TD.
     *
     * @param array $obj
     *
     * @return bool
     */
    protected function mediateDataAndMetadata(&$obj)
    {
        parent::mediateDataAndMetadata($obj);
        $view = $this->getView();
        
        $delTypeFld = array();
        $view->findComponents(array('path' => 'DELTYPE'), EditorComponentFactory::TYPE_FIELD, $delTypeFld);
        $deltypes = $delTypeFld[0]->getProperty('type');
       
        $fields = "";
        if ($obj['DOCID'] == StkitDocumentManager::BUILDKIT || $obj['DOCID'] == StkitDocumentManager::DISKIT) {
            $obj['CONVTYPE'] = 'Close Transaction';
            self::findElements($view->params['child'], array('path' => 'CONVTYPE'), $fields, $cfields);
            foreach ( $cfields as $i => $field) {
                $cfields[$i]['value'] = 'Close Transaction';
                $cfields[$i]['disabled'] = true;
            }

            $cfields = array();
            $obj['EDITTYPE'] = 'Edit in Draft Only';
            self::findElements($view->params['child'], array('path' => 'EDITTYPE'), $fields, $cfields);
            foreach ( $cfields as $i => $field) {
                $cfields[$i]['value'] = 'Edit in Draft Only';
                $cfields[$i]['disabled'] = true;
            }

            $cfields = array();
            $obj['DELTYPE'] = 'Delete in Draft Only';
            self::findElements($view->params['child'], array('path' => 'DELTYPE'), $fields, $cfields);
            foreach ( $cfields as $i => $field) {
                $cfields[$i]['value'] = 'Delete in Draft Only';
                $cfields[$i]['disabled'] = true;
            }
            
            $deltypes['validvalues'] = array ('No Delete','Before Printing', 'Delete in Draft Only', 'All');
            $deltypes['validlabels'] =
                array( I18N::getSingleToken('IA.NO_DELETE'), I18N::getSingleToken('IA.BEFORE_PRINTING'),
                       I18N::getSingleToken('IA.DELETE_IN_DRAFT_ONLY'), I18N::getSingleToken('IA.ALL') );
            $deltypes['_validivalues'] = array ('N','P','D', 'H');
            
            //remove subtotal checkbox -- mmahur
            $cfields = array();
            self::findElements($view->params['child'], array('path' => 'SHOW_TOTALS'), $fields, $cfields);
            $obj['SHOW_TOTALS'] = false;
            foreach ( $cfields as $i => $field) {
                $cfields[$i]['value'] = false;
                $cfields[$i]['disabled'] = true;
            }


            $view->findAndSetProperty(
                array('path' => 'DOCPAR_TOTALS'), array('readonly' => true),
                EditorComponentFactory::TYPE_GRID
            );

            // remove subtotal and "Convert From" tabs -- mmahur
            $view->findAndSetProperty(
                array('path' => 'DOCPAR_SUBTOTAL'), array('hidden' => true),
                EditorComponentFactory::TYPE_GRID
            );

            $view->findAndSetProperty(
                array('id' => 'trx_conversion_section'),
                array('helpText' => ''),
                EditorComponentFactory::TYPE_SECTION
            );

            $view->findAndSetProperty(
                array('path' => 'DOCPAR_RECALLS'), array('hidden' => true),
                EditorComponentFactory::TYPE_GRID
            );

        } else {
            $deltypes['validvalues'] = array('No Delete', 'Before Printing', 'All');
            $deltypes['validlabels'] =
                array( I18N::getSingleToken('IA.NO_DELETE'), I18N::getSingleToken('IA.BEFORE_PRINTING'),
                       I18N::getSingleToken('IA.ALL') );
            $deltypes['_validivalues'] = array('N', 'P', 'H');
        }
        
        $delTypeFld[0]->setProperty('type', $deltypes);

        if (
            $obj['DOCID'] == ICTransferManager::OUTDOCTYPE
            || $obj['DOCID'] == ICTransferManager::INTRANSITDOCTYPE
            || $obj['DOCID'] == ICTransferManager::INDOCTYPE
            || $obj['DOCID'] == InvDocumentManager::LANDEDCOSTDOCTYPE
            || $obj['DOCID'] == InvDocumentManager::LANDEDCOSTESTDOCTYPE
            || $obj['DOCID'] == InvDocumentManager::LANDEDCOSTESTREVDOCTYPE
            || $obj['DOCID'] == ICCycleCountManager::ADJINCREASEDOCTYPE
            || $obj['DOCID'] == ICCycleCountManager::ADJDECREASEDOCTYPE
            || $obj['DOCID'] == ICCycleCountManager::ADJDAMAGEDDOCTYPE
            || $obj['DOCID'] == PODocumentManager::SUPPLIESISSUEDOCTYPE
            || $obj['DOCID'] == PODocumentManager::SUPPLIESRETURNDOCTYPE
        ) {

            $readonlyFlds = array(
                'CATEGORY',
                'DOCCLASS',
                'STATUS',
                'CONVTYPE',
                'CREATETYPE',
                'EDITTYPE',
                'DELTYPE',
                'TD_CREATION_RULE',
                'SHOW_TOTALS'
            );

            foreach ($readonlyFlds as $fld) {
                $view->findAndSetProperty(
                    array('path' => $fld), array('disabled' => true), EditorComponentFactory::TYPE_FIELD
                );
            }

            if ($obj['DOCID'] != InvDocumentManager::LANDEDCOSTDOCTYPE &&
                $obj['DOCID'] != InvDocumentManager::LANDEDCOSTESTDOCTYPE &&
                $obj['DOCID'] != InvDocumentManager::LANDEDCOSTESTREVDOCTYPE &&
                $obj['DOCID'] != PODocumentManager::SUPPLIESISSUEDOCTYPE &&
                $obj['DOCID'] != PODocumentManager::SUPPLIESRETURNDOCTYPE) {
                $view->findAndSetProperty(
                    array('id' => 'sequnceNumbering'), array('hidden' => true),
                    EditorComponentFactory::TYPE_SUBSECTION
                );
            }
            $view->findAndSetProperty(
                array('id' => 'user_group_permission_section'), array('hidden' => true),
                EditorComponentFactory::TYPE_SECTION
            );
            $view->findAndSetProperty(
                array('id' => 'trx_conversion_section'), array('helpText' => ''),
                EditorComponentFactory::TYPE_SECTION
            );
            $view->findAndSetProperty(
                array('path' => 'DOCPAR_RECALLS'), array('readonly' => true),
                EditorComponentFactory::TYPE_GRID
            );
            $view->findAndSetProperty(
                array('path' => 'DOCPAR_TOTALS'), array('readonly' => true),
                EditorComponentFactory::TYPE_GRID
            );

            $view->findAndSetProperty(
                array('id' => 'entity_properties_tab'), array('hidden' => true),
                EditorComponentFactory::TYPE_TAB
            );

            if ($obj['DOCID'] === PODocumentManager::SUPPLIESISSUEDOCTYPE
                || $obj['DOCID'] === PODocumentManager::SUPPLIESRETURNDOCTYPE) {
                $view->findAndSetProperty(array('id' => 'accounting_section'), array('hidden' => true),EditorComponentFactory::TYPE_SUBSECTION);
                $view->findAndSetProperty(array('id' => 'workflow_section'), array('hidden' => true), EditorComponentFactory::TYPE_SECTION);
            }
        }

        if (in_array(
            $obj['DOCID'], DocumentParamsManager::$systemGeneratedTDs
        ) && $obj['DOCID'] !== ICCycleCountManager::ADJDAMAGEDDOCTYPE
        ) {
            $cfields = array();
            self::findElements($view->params['child'], array('path' => 'UPDATES_GL'), $fields, $cfields);
            /** @noinspection PhpUndefinedVariableInspection */
            $obj['UPDATES_GL'] = $updatesGL;
            foreach ( $cfields as $i => $field) {
                $cfields[$i]['disabled'] = true;
            }

        }

        $readonlyFlds = array(
            'PRICELISTID',
            'SPECIAL_PRICELISTID',

        );

        foreach ($readonlyFlds as $fld) {
            $view->findAndSetProperty(
                array('path' => $fld), array('disabled' => true), EditorComponentFactory::TYPE_FIELD
            );
        }

        // If the configuration is standard hide certain fields
        $isAdvancedConfiguration = IsAdvancedConfiguration();
        if (!$isAdvancedConfiguration) {
            $this->adjustForStandardConfiguration($obj);
        }
        return true;

    }

    /**
     * Restrict Duplication for the Build Kits and Disassemble Kits TDs.
     *
     * @return bool
     */
    protected function CanDuplicate()
    {
        $obj = $this->getBusinessObject();
        if (in_array($obj['DOCID'], DocumentParamsManager::$systemGeneratedTDs)) {
            return false;
        }

        return parent::CanDuplicate();
    }

    /**
     * @return string[] Token(s) required by js
     */
    protected function getFormTokens() : array
    {
        $this->textTokens[] = 'IA.DEFAULT_WAREHOUSE_NOT_PROVIDED';
        return parent::getFormTokens();
    }

    /**
     * @param array &$obj
     *
     * @return bool
     */
    protected function transformBizObjectToView(&$obj)
    {
        // This should only be used by the REST API, so clear it from the mappings
        foreach ($obj['DOCPAR_INVGL'] ?? [] as $index => $docParInvGl) {
            unset($obj['DOCPAR_INVGL'][$index]['GLACCTNUMBER']);
        }
        return parent::transformBizObjectToView($obj);
    }
}