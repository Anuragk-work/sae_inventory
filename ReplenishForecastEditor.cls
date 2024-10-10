<?php
/**
 * =============================================================================
 *
 * @filesource ReplenishmentEditor.cls
 * @author
 * @copyright  2018, Intacct Corporation, All Rights Reserved
 *
 * Intacct Corporation Proprietary Information.
 * This document contains trade secret data that belongs to Intacct
 * corporation and is protected by the copyright laws. Information herein
 * may not be used, copied or disclosed in whole or part without prior
 * written consent from Intacct Corporation.
 * =============================================================================
 */


/**
 * class ReplenishmentEditor extends FormEditor
 */
class ReplenishForecastEditor extends FormEditor
{
    /**
     * Replenish forecast specific tokens
     * @var string[]
     */
    private $replenishForecastTokens = [
        'IA.CHANGED_DATA_WARNING_TEXT',
        'IA.CONTINUE_WITHOUT_SAVING_TEXT',
        'IA.NO_WAREHOUSE_INDICATED',
    ];

    /** @var string $mod */
    var $mod = 'inv';

    /**
     * @var array I18n mapping
     */
    protected $replenishmentTextMap = [];


    /** @var string $createforecastitem */
    var $createforecastitem = null;

    /**
     * @var mixed $itemaction
     */
    var $itemaction = null;

    /**
     * {{{ Constructor
     *
     * @param array $_params
     */
    function __construct($_params = [])
    {
        $itemaction = Request::$r->_itemaction;
        $this->itemaction = $itemaction;

        $item = Request::$r->_item;

        switch ($itemaction)
        {
            case 'edit':
                break;
            case 'create':
                $this->createforecastitem = $item;
                break;

        }
        $this->additionalTokens = array_merge($this->additionalTokens, $this->replenishForecastTokens);
        parent::__construct($_params);

        //Add handlers for buttons/menus on this form
        $this->addActionHandlers();
    }

    /**
     * mediateDataAndMetadata
     *
     * @param  array &$obj Object variable
     *
     * @return bool           true on success
     */
    protected function mediateDataAndMetadata(&$obj)
    {
        $ok = parent::mediateDataAndMetadata($obj);

        $this-> setfieldproperties();

        $obj['PAGECHANGED'] = false;
        $obj['CHANGEDDATAWARNINGTEXT'] = GT($this->replenishmentTextMap, 'IA.CHANGED_DATA_WARNING_TEXT')."<p></p>".GT($this->replenishmentTextMap, 'IA.CONTINUE_WITHOUT_SAVING_TEXT');

        if (!is_null( $this->createforecastitem))
        {
            $obj['ITEMID'] =  $this->createforecastitem;
        }

        $this->processPreviewActionWithObj($obj);

        return $ok;
    }


function setfieldproperties()
{


    // Get the current action value
//    $action = Request::$r->{$this->kAction};
    $do = $this->kDefaultVerbActions[Request::$r->_do];

    $fieldsToUpdate = [
    ];
    switch ($do)
    {
        case 'list':
            break;

        case 'edit':
            $fieldsToUpdate[] = ['field' => 'ITEMID', 'property' => 'readonly', 'value' => true, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,];
            $fieldsToUpdate[] = ['field' => 'NAME', 'property' => 'readonly', 'value' => false, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,];
            break;

        case 'create':
            break;

        case 'new':
            $itemreadonly =  ($this->itemaction == 'create')? true:false;
            $fieldsToUpdate[] = ['field' => 'ITEMID', 'property' => 'readonly', 'value' => $itemreadonly, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,];
            $fieldsToUpdate[] = ['field' => 'NAME', 'property' => 'readonly', 'value' => false, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,];
            $fieldsToUpdate[] = ['field' => 'FiltersSection', 'property' => 'hidden', 'value' => true, 'identifier' => 'id', 'type' => EditorComponentFactory::TYPE_SECTION,];
            break;

        case 'delete':
            break;

        case 'view':
            $fieldsToUpdate[] = ['field' => 'FROMDATE', 'property' => 'readonly', 'value' => false, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,];
            $fieldsToUpdate[] = ['field' => 'TODATE', 'property' => 'readonly', 'value' => false, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,];
            $fieldsToUpdate[] = ['field' => 'FROMWAREHOUSEID', 'property' => 'readonly', 'value' => false, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,];
            break;

        case 'nextcode':
            break;

        default:
            break;

    }

//    $fieldsToUpdate[] = ['field' => 'ConfirmExitWithChangedData', 'property' => 'height', 'value' => '275px', 'identifier' => 'id', 'type' => EditorComponentFactory::TYPE_FLOATING_PAGE,];
//    $fieldsToUpdate[] = ['field' => 'ConfirmExitWithChangedData', 'property' => 'width', 'value' => '325px', 'identifier' => 'id', 'type' => EditorComponentFactory::TYPE_FLOATING_PAGE,];
//    $fieldsToUpdate[] = ['field' => 'ConfirmExitWithChangedData', 'property' => 'min-height', 'value' => '275px', 'identifier' => 'id', 'type' => EditorComponentFactory::TYPE_FLOATING_PAGE,];
//    $fieldsToUpdate[] = ['field' => 'ConfirmExitWithChangedData', 'property' => 'min-width', 'value' => '325px', 'identifier' => 'id', 'type' => EditorComponentFactory::TYPE_FLOATING_PAGE,];


    $view = $this->getView();
    foreach ($fieldsToUpdate as $value)
    {
        // set the column fields to hide/show
        $grid = [];
        $view->findComponents([$value['identifier'] => $value['field']], $value['type'], $grid);

        foreach ($grid as $field)
        {
            $field->setProperty($value['property'], $value['value']);
        }
    }


}

    /**
     * @param array $_params
     * @return bool
     * @throws Exception
     */
    public function handleSaveandFilterButton($_params)
    {
       // save data
       $ok =  $this->ProcessSaveAction($_params);

        // don't navigate away from page
        $this->state = $this->kShowEditState;

        // update filter
         $this->processPreviewAction($_params);
        return $ok;
    }

    /**
     * @param array $_params
     * @return bool
     * @throws Exception
     */
    public function handleFilterButton($_params)
    {
        return $this->processPreviewAction($_params);
    }

    /**
     * @param array $params
     *
     * @return bool
     * @throws Exception
     */
    protected function processPreviewAction($params)
    {
        $ok = true;
        $this->retrieveObjectFromView($params, $obj);


        $gManagerFactory = Globals::$g->gManagerFactory;
        $ReplenishForecastMgr = $gManagerFactory->getManager('ReplenishForecast');
        $filtertemplate = [
            'filters' => [],
            'orders'  => [],
        ];
        list($fromitemid) = explode('--', $obj['ITEMID']);
        $filtertemplate['filters'][][] = ['itemid', '= ', $fromitemid];

        // set noew object values from the retrieved object
        $result = $ReplenishForecastMgr->GetList($filtertemplate);
        $obj['NAME'] = $result[0]['NAME'];
        $obj['STATUS'] = $result[0]['STATUS'];
        $obj['ITEM_UOM'] = $result[0]['ITEM_UOM'];


        $ok = $this->processPreviewActionWithObj($obj) && $ok;

        return $ok;
    }


    /**
     * @param array $obj
     * @return bool
     */
    protected function processPreviewActionWithObj(&$obj)
    {
        $ok = true;
        $gManagerFactory = Globals::$g->gManagerFactory;
        $ReplenishForecastDetailMgr = $gManagerFactory->getManager('ReplenishForecastDetail');

        $obj['PAGECHANGED'] = false;

        $filtertemplate = [
            'filters' => [],
            'orders'  => [],
        ];

        $itemsfilter = $filtertemplate;
        $datefilter = $filtertemplate;
        $warehousefilter = $filtertemplate;
        $orderbyFilter = $filtertemplate;

        // get all the data from the form
        $this->setItemFilter($obj, $itemsfilter);
        $this->setDateFilter($obj, $datefilter);
        $this->setWarehouseFilter($obj, $warehousefilter);
        $this->setOrderbyFilter($obj, $orderbyFilter);

        // combine all the filters
        // need need to cast to (array) otherwise any null array will cause return of null
        $ListQueryparams['filters'][0] = array_merge(
            (array)$itemsfilter['filters'][0],
            (array)$datefilter['filters'][0],
            (array)$warehousefilter['filters'][0]
        );

        // do order by
        $ListQueryparams['orders'] = array_merge(
            (array)$orderbyFilter['orders']
        );


        $result = $ReplenishForecastDetailMgr->GetList($ListQueryparams);

        $obj['REPLENISH_FORECAST_ENTRIES_INFO'] = [];
        $ok = $ok && $this->convertDataToUI($result, $obj['REPLENISH_FORECAST_ENTRIES_INFO']);

        if (empty($obj['ITEM_UOM']))
        {
            $obj['ITEM_UOM'] = $obj['DEFAULT_UNIT_OF_MEASURE'];
        }

        return $ok;
    }

    /**
     * Convert the snapshot data to a structure that the UI can display
     *
     * @param array $snapshotData the snapshot data
     * @param array &$orderingLineItems the UI data to display
     *
     * @return bool                       true on success
     */
    private function convertDataToUI($snapshotData, &$orderingLineItems)
    {
        $ok = true;

        $rowcount = 0;

        foreach ($snapshotData as $aRow)
        {
            $thisrow = [];
            $thisrow['RECORDNO'] = $aRow['RECORDNO'];
            $thisrow['EFFECTIVEDATE'] = $aRow['EFFECTIVEDATE'];
            $thisrow['QUANTITY'] = $aRow['QUANTITY'];
            $thisrow['ITEM'] = $aRow['ITEMID'] . '--' . $aRow['ITEMNAME'];
            $thisrow['WAREHOUSE'] = $aRow['WAREHOUSEID'] . '--' . $aRow['WAREHOUSENAME'];


            $orderingLineItems[] = $thisrow;

            $rowcount++;
        }

        for (; $rowcount < 3; $rowcount++)
        {
            $thisrow =
                [
                    'RECORDNO'      => '',
                    'EFFECTIVEDATE' => '',
                    'QUANTITY'      => '',
                    'ITEM'          => '',
                    'WAREHOUSE'     => '',
                    '_isNewLine'     => true,
            ];

            $orderingLineItems[] = $thisrow;
        }
        return $ok;
    }


    /**
     * @param array $obj
     *
     * @param array $filterstring
     * @return bool
     */
    private function setItemFilter(array &$obj, & $filterstring)
    {
        $ok = true;
        if (isSpecified($obj['ITEMID']))
        {
            $fromItem = $obj['ITEMID'];
            $toItem = $obj['ITEMID'];

            /* ----------------- Filters -------------------*/
            list($fromitemid) = explode('--', $fromItem);
            $fromitemid = $fromitemid ? isl_trim(isl_htmlspecialchars($fromitemid)) : VARCHAR2_MIN;
            list($toitemid) = explode('--', $toItem);
            $toitemid = $toitemid ? isl_trim(isl_htmlspecialchars($toitemid)) : VARCHAR2_MAX;


            $filter = [];
            if ($fromitemid != '')
            {
                $filter [] = ['itemid', '>= ', "$fromitemid"];
            }
            if ($toitemid != '')
            {
                $filter [] = ['itemid', '<= ', "$toitemid"];
            }
            $filterstring['filters'][] = $filter;
        }
        else
        {
            $filterstring['filters'][] = [
                ['itemid', '= ', "null"],
            ];

        }
        return $ok;
    }

    /**
     * @param array $obj
     * @param array $filterstring
     * @return bool
     */
    private function setDateFilter(array &$obj, & $filterstring)
    {
        $ok = true;
        if (isSpecified($obj['FROMDATE']) || isSpecified($obj['TODATE']))
        {
            /* @var  ItemManager $itemManager */

            $fromDate = $obj['FROMDATE'];
            $toDate = $obj['TODATE'];

            /* ----------------- Date Filters -------------------*/
            // date filters
            $filter = [];
            if ($fromDate != '')
            {
                $filter [] = ['effectivedate', '>= ', "$fromDate"];
            }
            if ($toDate != '')
            {
                $filter [] = ['effectivedate', '<= ', "$toDate"];
            }
            $filterstring['filters'][] = $filter;
        }
        return $ok;
    }


    /**
     * @param array $obj
     * @param array $filterstring
     * @return bool
     */
    private function setWarehouseFilter(array &$obj, & $filterstring)
    {
        $ok = true;
        if (isSpecified($obj['FROMWAREHOUSEID']))
        {
            /* @var  ItemManager $itemManager */

            $fromWarehouse = $obj['FROMWAREHOUSEID'];
            /* ----------------- Warehouse Filters -------------------*/
            // warehouse filters
            if ($fromWarehouse == '')
//            if ($fromWarehouse == '' && $toWarehouse == '')
            {
            }
            else
            {
                list($fromWarehouseid) = explode('--', $fromWarehouse);
                $fromWarehouse = $fromWarehouseid ? isl_trim(isl_htmlspecialchars($fromWarehouseid)) : VARCHAR2_MIN;
                if ($fromWarehouse == GT($this->replenishmentTextMap, 'IA.NO_WAREHOUSE_INDICATED'))
                {
                    // select records where warehouse is null
                    $filterstring['filters'][] = [
                        ['warehouseid', 'ISNULL', null],
                    ];

                }
                else
                {
                    $filterstring['filters'][] = [
                        ['warehouseid', '=', "$fromWarehouse"],
                    ];
                }
            }
        }
        return $ok;
    }


    /**
     * @param array $obj
     * @param array $filterstring
     * @return bool
     */
    private function setOrderbyFilter(array &$obj, & $filterstring)
    {
        $ok = true;
        $obj[0];
        /* -----------------  Filters -------------------*/
        //  filters

        $filterstring['orders'][] = ['EFFECTIVEDATE', 'desc'];
        $filterstring['orders'][] = ['WAREHOUSEID', 'asc'];

        return $ok;
    }


    /**
     * Override parent and handle currentView
     */
    protected function addActionHandlers()
    {
        $this->kActionHandlers['FilterButton'] = [
            'handler' => 'handleFilterButton',
            'states'  => [
                $this->kShowViewState,
                $this->kShowEditState,
                $this->kShowNewState,
                $this->kInitState,
            ],
            'csrf'    => true,
        ];

                $this->kActionHandlers['SaveandFilterButton'] = [
                    'handler' => 'handleSaveandFilterButton',
                    'states'  => [
                        $this->kShowViewState,
                        $this->kShowEditState,
                        $this->kShowNewState,
                        $this->kInitState,
                    ],
                    'csrf'    => true,
                ];
    }


    /**
     * Get the list of JS files to include in the editor screen
     *
     * @return array    the list of JS files to include
     */
    protected function getJavaScriptFileNames()
    {
        $jsFiles = parent::getJavaScriptFileNames();
        $jsFiles[] = '../resources/js/replenishforecast.js';
        return $jsFiles;
    }


//    /**
//     * @param array $_params
//     * @param array $obj
//     * @param bool  $ok
//     *
//     * @return bool
//     */
//    protected function innerProcessSaveAction(&$_params, &$obj, $ok)
//    {
//        $ok &= parent::innerProcessSaveAction($_params, $obj, $ok);
//        return $ok;
//    }

//
//    protected function prepareObjectForCopyNew(&$obj)
//    {
//
////        $obj['ITEMNAME'] = null;
////        $obj['ITEMID'] = null;
////        $obj['RECORDNO'] = null;
//
//        unset($obj['ITEMNAME']);
//        unset($obj['ITEMID']);
//        unset($obj['RECORDNO']);
//
//        $ok = parent::prepareObjectForCopyNew($obj);
//
//
////
////        foreach ($obj[REPLENISH_FORECAST_ENTRIES_INFO] as $key => $value)
////        {
////            $obj[REPLENISH_FORECAST_ENTRIES_INFO][$key][ITEM] = null;
////            $obj[REPLENISH_FORECAST_ENTRIES_INFO][$key][RECORDNO] = null;
////        }
//
//        return $ok;
//    }
//
//    /**
//     * No 'Duplicate' button
//     *
//     * @return bool
//     */
//    protected function CanDuplicate()
//    {
//        return true;
////        return false;
//    }

    /**
     * @param EditorGrid    $grid
     * @param EntityManager $entityMgr
     * @param array         $_obj
     */
    protected function innerCleanupLineItems($grid, $entityMgr, &$_obj)
    {

//        return parent::innerCleanupLineItems($grid, $entityMgr, $_obj);
            // Is there is no data to cleanup, no need to continue
            $path = $grid->getProperty('path');
            if (!is_array($_obj[$path]))
            {
                return;
            }

            if ($entityMgr)
            {
                $ownedObjects =& $entityMgr->GetOwnedObjects();
            }
            else
            {
                $ownedObjects = [];
            }

            // If this grid is an onwed object let's get the primary field from the manager
            $primaryfield = '';
            $mlineMgr = null;
            foreach ($ownedObjects as $ownedObject)
            {
                if ($ownedObject['path'] == $path)
                {
                    $entity = $ownedObject['entity'];
                    $mlineMgr = $this->GetManager($entity);

                    $primaryfield = $mlineMgr->GetMultiLinePrimaryField();
                    break;
                }
            }

            $firstfield = '';
            if (isset($primaryfield) && $primaryfield != '')
            {
                /*    We are checking for the existance of the primary field here because of a
                 difference in paradigm between the APBill/ARInvoice classes and the Advance classes:
                 The former define their object as having no ACCOUNTLABELKEY field even when labels
                 are turned on (putting the values in a GLACCOUNT field and switching that field's
                 definition in the Editor's logic. The latter define both and only hide one or the
                 other depending upon the context.
                 We should be moving toward the paradigm adapted by the latter classes.
                 (per Steve Clode) -- PCS
                */
                $grid->findComponents(['path' => $primaryfield], EditorComponentFactory::TYPE_FIELD, $foundPrimary);
                if (count($foundPrimary))
                {
                    $firstfield = $primaryfield;
                }
            }
            // If we have no primary field we will get it from the grid component
            if (empty($firstfield))
            {
                $firstfield = $grid->getProperty('primaryField');
            }
            $field2 = is_array($grid->params['column'][1]) && is_array($grid->params['column'][1]['field'][0]) ? $grid->params['column'][1]['field'][0]['path'] : '';
            $field3 = is_array($grid->params['column'][2]) && is_array($grid->params['column'][2]['field'][0]) ? $grid->params['column'][2]['field'][0]['path'] : '';

            $nlines = [];
            // Get the line details
            $lineDetails = [];
            $grid->findComponents(null, EditorComponentFactory::TYPE_LINEDETAILS, $lineDetails);

            // Get the child grid components
            $childGrids = [];
            if (count($lineDetails) > 0)
            {
                $lineDetails[0]->findComponents(null, EditorComponentFactory::TYPE_GRID, $childGrids);
            }

            // Cleanup the data
            foreach ($_obj[$path] as $line)
            {
                if (!empty($firstfield)
                    && ((!isset($line[$firstfield]) || $line[$firstfield] == '') && (!isset($line[$field2])) && (!isset($line[$field3])))
                )
                {
                    continue;
                }
                // Cleanup the child grids
                foreach ($childGrids as $childGrid)
                {
                    $this->innerCleanupLineItems($childGrid, $mlineMgr, $line);
                }
                $nlines[] = $line;
            }
            $_obj[$path] = $nlines;
        }


    /**
     * @return bool
     */
    protected function CanDuplicate()
    {
        return false;
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function transformBizObjectToView(&$obj)
    {
        $this->replenishmentTextMap = getLocalizedText(I18N::tokenArrayToObjectArray($this->additionalTokens), $errMsg);
        return parent::transformBizObjectToView($obj);
    }

    /**
     * I18N. Collection of tokens used primarily in JavaScript.
     *
     * @return string[]
     */
    protected function getFormTokens() : array
    {
        $this->textTokens = array_merge($this->textTokens, ['IA.DUPLICATE_ROWS_AND','IA.DUPLICATE_ROWS_ITEMS',
                            'IA.DUPLICATE_ROWS_IN_THE_FORECAST_ENTRIES', 'IA.DUPLICATE_ROWS_MESSAGE']);
        return parent::getFormTokens();
    }


}


