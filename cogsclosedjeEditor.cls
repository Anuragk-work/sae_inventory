<?php
/**
 * =============================================================================
 *
 * FILE:        BinEditor.cls
 * AUTHOR:      Sri Vidya
 * DESCRIPTION: Editor class for handelling Bin object
 *
 * (C)2000,2009 Intacct Corporation, All Rights Reserved
 *
 * Intacct Corporation Proprietary Information.
 * This document contains trade secret data that belongs to Intacct
 * corporation and is protected by the copyright laws. Information herein
 * may not be used, copied or disclosed in whole or part without prior
 * written consent from Intacct Corporation.
 * =============================================================================
 */

/**
 * Editor class for Bin object
 */
class COGSClosedJeEditor extends FormEditor
{


    /**
     * @var bool $needsAdjustment
     */
    private $needsAdjustment = false;

    /**
     * COGSClosedJeEditor specific tokens
     *
     * @var string[] $priorPeriodCOGSTokens
     */
    private $priorPeriodCOGSTokens = [
        'IA.COGSCLOSEDJE_POSTED',
        'IA.RECOMMENDED',
        'IA.MANUALLY_ADJ',
        'IA.UNKNOWN_STATUS',
        'IA.POSTING_DATE_INVALID_ENTER_VALID_POSTING_DATE',
        'IA.ROWS_SELECTED_ON_THIS_PAGE',
        'IA.ADJUSTMENTS_MARKED_MANUALLY_ADJUSTED',
        'IA.ADJUSTMENT_MARKED_MANUALLY_ADJUSTED',
        'IA.COGSCLOSEDJE_MARKED',
        'IA.ADJUSTMENTS_UNMARKED_MANUALLY_ADJUSTED',
        'IA.ADJUSTMENT_UNMARKED_MANUALLY_ADJUSTED',
        'IA.COGSCLOSEDJE_UNMARKED',
        'IA.ADJUSTMENTS_SUCCESSFULLY_POSTED',
        'IA.ADJUSTMENT_SUCCESSFULLY_POSTED',
        'IA.ADJUSTMENTS_CAN_ONLY_BE_POSTED_IN_OPEN_PERIODS',
        'IA.ADJUSTMENTS_SUCCESSFULLY_DELETED',
        'IA.ADJUSTMENT_SUCCESSFULLY_DELETED',
        'IA.ADJUSTMENTS_CAN_ONLY_BE_DELETED_IN_OPEN_PERIODS',
        'IA.COGSCLOSEDJE_DELETED',
        'IA.RECORD_UNKNOWN_ADJUSTMENT',
        'IA.UNKNOWN_ADJUSTMENT',
        'IA.INVALID_ACTION',
        'IA.ADJUSTMENTS_FAILED_ACTION',
        'IA.ADJUSTMENT_FAILED_ACTION',
    ];

    /**
     * @param array $_params Initial params
     */
    public function __construct($_params = [])
    {

        parent::__construct($_params);

        $this->additionalTokens = array_merge($this->additionalTokens, $this->priorPeriodCOGSTokens);

        $this->addPreviewAction();
    }


    /**
     * Get the list of JS files to include in the editor screen
     *
     * @return array    the list of JS files to include
     */
    protected function getJavaScriptFileNames()
    {
        $jsFiles = parent::getJavaScriptFileNames();
        $jsFiles[] = '../resources/js/cogsclosedje.js';
        return $jsFiles;
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


        if ($ok)
        {
            $obj['rowsselected'] = 0;
            $obj['rowstotal'] = !is_array($obj['COGS_CLOSEDJE_INFO']) ? 0 : count($obj['COGS_CLOSEDJE_INFO']);

            $this->setDisplayedElementsFromAction($obj);
            $this->setNumberOfElementsCheckedString($obj);
        }
        return $ok;
    }


    /**
     * @param string $state
     *
     * @return array
     */
    public function getStandardButtons($state)
    {
        $buttons = parent::getStandardButtons($state);

        if ($state == 'shownew')
        {
            $newbuttons = [];
            // Remove save and new button if the call is from dashboard
            foreach ($buttons as $value)
            {
                switch ($value['id'])
                {
                    case 'saveandnewbuttid':
                    case 'savebuttid':
                        // remove these values
                        break;

                    default:
                        $newbuttons[] = $value;
                        break;
                }
            }
            $buttons = $newbuttons;
        }

        return $buttons;
    }


    /**
     * Override parent and handle currentView
     */
    protected function addPreviewAction()
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

        $this->kActionHandlers['Manualresolve'] = [
            'handler' => 'handleManualresolveButton',
            'states'  => [
                $this->kShowViewState,
                $this->kShowEditState,
                $this->kShowNewState,
                $this->kInitState,
            ],
        ];

        $this->kActionHandlers['Manualreverse'] = [
            'handler' => 'handleManualreverseButton',
            'states'  => [
                $this->kShowViewState,
                $this->kShowEditState,
                $this->kShowNewState,
                $this->kInitState,
            ],
        ];

        $this->kActionHandlers['Postcogs'] = [
            'handler' => 'handlePostButton',
            'states'  => [
                $this->kShowViewState,
                $this->kShowEditState,
                $this->kShowNewState,
                $this->kInitState,
            ],
        ];

        $this->kActionHandlers['Reversecogs'] = [
            'handler' => 'handleReverseButton',
            'states'  => [
                $this->kShowViewState,
                $this->kShowEditState,
                $this->kShowNewState,
                $this->kInitState,
            ],
        ];

        $this->kActionHandlers['validatepostingdate'] = [
            'handler' => 'validatepostingdate',
            'states'  => [
                $this->kShowViewState,
                $this->kShowEditState,
                $this->kShowNewState,
                $this->kInitState,
            ],
        ];
    }


    /**
     * @param string $date
     * @return bool
     */
    function validatepostingdate($date)
    {
        $valid = !empty($date) && ValidateDate($date);
        return $valid;
    }


    /**
     * @param array $obj
     */
    function setNumberOfElementsCheckedString(&$obj)
    {
        $tokens = [
            [
                'id' => 'IA.ROWS_SELECTED_ON_THIS_PAGE',
                'placeHolders' => [
                    ['name' => 'ROWS_SELECTED', 'value' => $obj['rowsselected']],
                    ['name' => 'ROWS_TOTAL', 'value' => $obj['rowstotal']]
                ]
            ]
        ];
        $text = getLocalizedTextWithThrow($tokens);
        $obj['NUMBEROFSELECTEDROWS'] = GT($text, 'IA.ROWS_SELECTED_ON_THIS_PAGE');

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

        $obj['POSTINGDATE'] = GetCompanyOpenDate(true);
        $gManagerFactory = Globals::$g->gManagerFactory;
        $cogsclosedjeMgr = $gManagerFactory->getManager('cogsclosedje');
        $filtertemplate = [
            'filters' => [],
            'orders'  => [],
        ];

        $actionfilter = $filtertemplate;
        $itemsfilter = $filtertemplate;
        $datefilter = $filtertemplate;
        $warehousefilter = $filtertemplate;
        $locationfilter = $filtertemplate;
        $customerfilter = $filtertemplate;
        $needadjustmentfilter = $filtertemplate;
        $recordtypefilter = $filtertemplate;
        $orderbyFilter = $filtertemplate;

        // get all the data from the form
        $this->setActionFilter($obj, $actionfilter);
        $this->setItemFilter($obj, $itemsfilter);
        $this->setDateFilter($obj, $datefilter);
        $this->setWarehouseFilter($obj, $warehousefilter);
        $this->setLocationFilter($obj, $locationfilter);
        $this->setCustomerFilter($obj, $customerfilter);
        $this->setNeedadjustmentFilter($obj, $needadjustmentfilter);
        $this->setOrderbyFilter($obj, $orderbyFilter);


        $ListQueryparams = $filtertemplate;

        // combine all the filters
        // need need to cast to (array) otherwise any null array will cause return of null
        $ListQueryparams['filters'][0] = array_merge(
            (array)$actionfilter['filters'][0],
            (array)$itemsfilter['filters'][0],
            (array)$datefilter['filters'][0],
            (array)$warehousefilter['filters'][0],
            (array)$locationfilter['filters'][0],
            (array)$customerfilter['filters'][0],
            (array)$needadjustmentfilter['filters'][0],
            (array)$recordtypefilter['filters'][0]
        );

        // do order by
        $ListQueryparams['orders'] = array_merge(
            (array)$orderbyFilter['orders']
        );
        $result = $cogsclosedjeMgr->GetList($ListQueryparams);

        $obj['INCLUDE_ALL_ON_PAGE'] = false;
        $obj['rowsselected'] = 0;
        $obj['rowstotal'] = count($result);
        $this->setNumberOfElementsCheckedString($obj);

        $obj['NORESULTSMESSAGE'] = 'IA.NO_RESULT_FOR_SELECTED_FILTERS';

        $obj['COGS_CLOSEDJE_INFO'] = [];
        $ok = $ok && $this->convertDataToUI($result, $obj['COGS_CLOSEDJE_INFO']);

        $ok = $ok && $this->setDisplayedElementsFromAction($obj);

        $action = Request::$r->_action;

        if ($action != 'FilterButton')
        {
            $gManagerFactory = Globals::$g->gManagerFactory;
            $cogsclosedjeMgr = $gManagerFactory->getManager('cogsclosedje');
            $recordscomitted = $cogsclosedjeMgr->commitStatus;
            $rowsSuccess = $recordscomitted['SUCCESS'] ?: 0;
            $rowsFail = $recordscomitted['FAIL'] ?: 0;
            $addSfail = ($rowsFail > 1) ? "s" : "";

            $showsuccessmesage = $rowsSuccess > 0;
            $showfailmesage = $rowsFail > 0;

            $additionaldescription = "";
            // everything is ok
            switch (strtolower($action))
            {
                case 'manualresolve':
                    $tokens = [
                        [
                            'id' => 'IA.ADJUSTMENT_MARKED_MANUALLY_ADJUSTED',
                            'placeHolders' => [
                                ['name' => 'ROWS_SUCCESS', 'value' => $rowsSuccess],
                            ]
                        ],
                        [
                            'id' => 'IA.ADJUSTMENTS_MARKED_MANUALLY_ADJUSTED',
                            'placeHolders' => [
                                ['name' => 'ROWS_SUCCESS', 'value' => $rowsSuccess],
                            ]
                        ]
                    ];
                    $text = getLocalizedTextWithThrow($tokens);
                    $confirmation = GT($text, ($rowsSuccess > 1)?
                                                        'IA.ADJUSTMENTS_MARKED_MANUALLY_ADJUSTED' :
                                                        'IA.ADJUSTMENT_MARKED_MANUALLY_ADJUSTED');
                    $actiontext = I18N::getSingleToken('IA.COGSCLOSEDJE_MARKED');
                    break;
                case 'manualreverse' :
                    $tokens = [
                        [
                            'id' => 'IA.ADJUSTMENT_UNMARKED_MANUALLY_ADJUSTED',
                            'placeHolders' => [
                                ['name' => 'ROWS_SUCCESS', 'value' => $rowsSuccess],
                            ]
                        ],
                        [
                            'id' => 'IA.ADJUSTMENTS_UNMARKED_MANUALLY_ADJUSTED',
                            'placeHolders' => [
                                ['name' => 'ROWS_SUCCESS', 'value' => $rowsSuccess],
                            ]
                        ]
                    ];
                    $text = getLocalizedTextWithThrow($tokens);
                    $confirmation = GT($text, ($rowsSuccess > 1)?
                                                        'IA.ADJUSTMENTS_UNMARKED_MANUALLY_ADJUSTED' :
                                                        'IA.ADJUSTMENT_UNMARKED_MANUALLY_ADJUSTED');
                    $actiontext = I18N::getSingleToken('IA.COGSCLOSEDJE_UNMARKED');
                    break;
                case 'postcogs' :
                    $tokens = [
                        [
                            'id' => 'IA.ADJUSTMENT_SUCCESSFULLY_POSTED',
                            'placeHolders' => [
                                ['name' => 'ROWS_SUCCESS', 'value' => $rowsSuccess],
                            ]
                        ],
                        [
                            'id' => 'IA.ADJUSTMENTS_SUCCESSFULLY_POSTED',
                            'placeHolders' => [
                                ['name' => 'ROWS_SUCCESS', 'value' => $rowsSuccess],
                            ]
                        ]
                    ];
                    $text = getLocalizedTextWithThrow($tokens);
                    $confirmation = GT($text, ($rowsSuccess > 1)?
                                                        'IA.ADJUSTMENTS_SUCCESSFULLY_POSTED' :
                                                        'IA.ADJUSTMENT_SUCCESSFULLY_POSTED');
                    $additionaldescription = "";
                    if ($showfailmesage) {
                        if (! Globals::$g->gErr->isEmpty()) {
                            $additionaldescription = Globals::$g->gErr->myToString(true, 1);
                            $additionaldescription = str_replace(['[!!', '!!]'], ['', ''], $additionaldescription );
                        } else {
                            $additionaldescription =
                                I18N::getSingleToken('IA.ADJUSTMENTS_CAN_ONLY_BE_POSTED_IN_OPEN_PERIODS');
                        }
                    }
                    $actiontext = I18N::getSingleToken('IA.COGSCLOSEDJE_POSTED');
                    break;

                case 'reversecogs' :
                    $tokens = [
                        [
                            'id' => 'IA.ADJUSTMENT_SUCCESSFULLY_DELETED',
                            'placeHolders' => [
                                ['name' => 'ROWS_SUCCESS', 'value' => $rowsSuccess],
                            ]
                        ],
                        [
                            'id' => 'IA.ADJUSTMENTS_SUCCESSFULLY_DELETED',
                            'placeHolders' => [
                                ['name' => 'ROWS_SUCCESS', 'value' => $rowsSuccess],
                            ]
                        ]
                    ];
                    $text = getLocalizedTextWithThrow($tokens);
                    $confirmation = GT($text, ($rowsSuccess > 1)?
                        'IA.ADJUSTMENTS_SUCCESSFULLY_DELETED' :
                        'IA.ADJUSTMENT_SUCCESSFULLY_DELETED');
                    $additionaldescription =
                        $showfailmesage ? I18N::getSingleToken('IA.ADJUSTMENTS_CAN_ONLY_BE_DELETED_IN_OPEN_PERIODS')
                            : '';
                    $actiontext = I18N::getSingleToken('IA.COGSCLOSEDJE_DELETED');
                    break;
                default:
                    $tokens = [
                        [
                            'id' => 'IA.RECORD_UNKNOWN_ADJUSTMENT',
                            'placeHolders' => [
                                ['name' => 'RESULT', 'value' => $result],
                            ]
                        ]
                    ];
                    $text = getLocalizedTextWithThrow($tokens);
                    $confirmation = GT($text, 'IA.RECORD_UNKNOWN_ADJUSTMENT');
                    $additionaldescription = I18N::getSingleToken('IA.UNKNOWN_ADJUSTMENT');
                    $actiontext = I18N::getSingleToken('IA.INVALID_ACTION');
                    break;
            }
            if ($showfailmesage)
            {
                // override default message
                $warnMessage = '';
                $messages = $recordscomitted['MESSAGE'];
                foreach ($messages as $msg)
                {
                    $warnMessage .= $msg . '<br>';
                    $additionaldescription = $warnMessage;
                }

                // create failed message
                $failtext = "";
                if ($showfailmesage) {
                    $tokens = [
                        [
                            'id' => 'IA.ADJUSTMENT_FAILED_ACTION',
                            'placeHolders' => [
                                ['name' => 'ROWS_FAIL', 'value' => $rowsFail],
                                ['name' => 'ACTION', 'value' => $actiontext],
                            ]
                        ],
                        [
                            'id' => 'IA.ADJUSTMENTS_FAILED_ACTION',
                            'placeHolders' => [
                                ['name' => 'ROWS_FAIL', 'value' => $rowsFail],
                                ['name' => 'ACTION', 'value' => $actiontext],
                            ]
                        ]
                    ];
                    $text = getLocalizedTextWithThrow($tokens);
                    $failtext = GT($text, ($addSfail > 1)?
                                    'IA.ADJUSTMENTS_FAILED_ACTION' :
                                    'IA.ADJUSTMENT_FAILED_ACTION');

                }
                $successtext = "";
                if ($rowsSuccess > 0) {
                    $tokens = [
                        [
                            'id' => 'IA.ADJUSTMENTS_ACTION_SUCCESSFULLY',
                            'placeHolders' => [
                                ['name' => 'ROWS_SUCCESS', 'value' => $rowsSuccess],
                                ['name' => 'ACTION', 'value' => $actiontext],
                            ]
                        ]
                    ];
                    $text = getLocalizedTextWithThrow($tokens);
                    $successtext = GT($text, 'IA.ADJUSTMENTS_ACTION_SUCCESSFULLY');
                }
                $confirmation = $failtext . "<br>" . $successtext . "<br>" . $additionaldescription;
                Globals::$g->gErr->AddWarning($confirmation);
                $this->SetWarningMessage($confirmation);
            }
            else
            {
                if ($showsuccessmesage)
                {
                    $this->SetMessage($confirmation);
                }
                else
                {
                    // zero records processed,
                    // show message created by other routines
                    $warnMessage = '';
                    $messages = $recordscomitted['MESSAGE'];
                    foreach ($messages as $msg)
                    {
                        $warnMessage .= $msg . '<br>';
                    }
                    Globals::$g->gErr->AddWarning($warnMessage);
                    $this->SetWarningMessage($warnMessage);
                }
            }
        }
        return $ok;
    }

    /**
     * @return bool
     */
    protected function getShowRepeatMsg()
    {
        return false;
    }


    /**
     * @param array $obj
     * @param array $filterstring
     * @return bool
     */
    private function setActionFilter(array &$obj, & $filterstring)
    {
        $ok = true;
        if (isSpecified($obj['ACTION']))
        {
            switch ($obj['ACTION'])
            {
                case 'post and manual':
                    $filterstring['filters'][] = [
                        ['NEEDSADJUSTMENT', '=', "true"],
                    ];
                    break;

                case 'reverse':
                    // only show records in open periods
                    $filterstring['filters'][] = [
                        ['NEEDSADJUSTMENT', '=', "false"],
                        ['MANUAL_ADJUSTMENT', '=', "false"],
                    ];
                    break;

                case 'unmarkmanual':
                    $filterstring['filters'][] = [
                        ['NEEDSADJUSTMENT', '=', "false"],
                        ['MANUAL_ADJUSTMENT', '=', "true"],
                    ];
                    break;

                case 'viewall':
                    // nothing to do
                    break;

                default:
                    // nothing to do
                    break;
            }
        }
        return $ok;
    }


    /**
     * @param array $obj
     * @return bool
     */
    private function setDisplayedElementsFromAction(array &$obj)
    {
        $ok = true;
        // hide fields in table
        $fieldsToUpdate = [
            ['field' => 'RECORD_STATUS', 'property' => 'hidden', 'value' => true, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,],
            ['field' => 'INCLUDED', 'property' => 'hidden', 'value' => false, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,],
            ['field' => 'NUMBEROFSELECTEDROWS', 'property' => 'hidden', 'value' => false, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,],
            ['field' => 'ADJUSTMENT_TRANSACTION', 'property' => 'hidden', 'value' => true, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,],
            ['field' => 'ADJUSTMENT_DATE', 'property' => 'hidden', 'value' => true, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,],
            ['field' => 'PREVIOUSADJUSTAMOUNT', 'property' => 'hidden', 'value' => true, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,],
            ['field' => 'ADJUSTAMOUNT', 'property' => 'hidden', 'value' => false, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,],
        ];

        // hide buttons
        $buttonstoHide = [
            ['field' => 'manualresolve', 'hide' => true, 'identifier' => 'id', 'type' => EditorComponentFactory::TYPE_BUTTONS,],
            ['field' => 'manualreverse', 'hide' => true, 'identifier' => 'id', 'type' => EditorComponentFactory::TYPE_BUTTONS,],
            ['field' => 'post', 'hide' => true, 'identifier' => 'id', 'type' => EditorComponentFactory::TYPE_BUTTONS,],
            ['field' => 'reverse', 'hide' => true, 'identifier' => 'id', 'type' => EditorComponentFactory::TYPE_BUTTONS,],
        ];

        if (isSpecified($obj['ACTION']))
        {
            // turn elements back on
            switch ($obj['ACTION'])
            {
                case 'post and manual':
                    $buttonstoHide[] = ['field' => 'post', 'hide' => false, 'identifier' => 'id', 'type' => EditorComponentFactory::TYPE_BUTTONS,];
                    $buttonstoHide[] = ['field' => 'manualresolve', 'hide' => false, 'identifier' => 'id', 'type' => EditorComponentFactory::TYPE_BUTTONS,];
                    $fieldsToUpdate[] = ['field' => 'resultstitle', 'property' => 'title', 'value' => 'IA.RECOMMENDED_ADJUSTMENTS', 'identifier' => 'id', 'type' => null,];
                    break;

                case 'reverse':
                    $buttonstoHide[] = ['field' => 'reverse', 'hide' => false, 'identifier' => 'id', 'type' => EditorComponentFactory::TYPE_BUTTONS,];
                    $fieldsToUpdate[] = ['field' => 'ADJUSTMENT_TRANSACTION', 'property' => 'hidden', 'value' => false, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,];
                    $fieldsToUpdate[] = ['field' => 'ADJUSTMENT_DATE', 'property' => 'hidden', 'value' => false, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,];
                    $fieldsToUpdate[] = ['field' => 'ADJUSTAMOUNT', 'property' => 'hidden', 'value' => true, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,];
                    $fieldsToUpdate[] = ['field' => 'PREVIOUSADJUSTAMOUNT', 'property' => 'hidden', 'value' => false, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,];
                    $fieldsToUpdate[] = ['field' => 'resultstitle', 'property' => 'title', 'value' => 'IA.POSTED_ADJUSTMENTS', 'identifier' => 'id', 'type' => null,];
                    break;


                case 'unmarkmanual':
                    $buttonstoHide[] = ['field' => 'manualreverse', 'hide' => false, 'identifier' => 'id', 'type' => EditorComponentFactory::TYPE_BUTTONS,];
                    $fieldsToUpdate[] = ['field' => 'resultstitle', 'property' => 'title', 'value' => 'IA.MANUALLY_POSTED_ADJUSTMENTS', 'identifier' => 'id', 'type' => null,];
                    break;

                case 'viewall':
                    $fieldsToUpdate[] = ['field' => 'RECORD_STATUS', 'property' => 'hidden', 'value' => false, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,];
                    $fieldsToUpdate[] = ['field' => 'INCLUDED', 'property' => 'hidden', 'value' => true, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,];
                    $fieldsToUpdate[] = ['field' => 'NUMBEROFSELECTEDROWS', 'property' => 'hidden', 'value' => true, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,];
                    $fieldsToUpdate[] = ['field' => 'ADJUSTMENT_TRANSACTION', 'property' => 'hidden', 'value' => false, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,];
                    $fieldsToUpdate[] = ['field' => 'ADJUSTMENT_DATE', 'property' => 'hidden', 'value' => false, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,];
                    $fieldsToUpdate[] = ['field' => 'PREVIOUSADJUSTAMOUNT', 'property' => 'hidden', 'value' => false, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,];
                    $fieldsToUpdate[] = ['field' => 'ADJUSTAMOUNT', 'property' => 'hidden', 'value' => false, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,];
                    $fieldsToUpdate[] = ['field' => 'resultstitle', 'property' => 'title', 'value' => 'IA.ALL_ADJUSTMENTS', 'identifier' => 'id', 'type' => null,];
                    break;

                default:
                    // hide everything
                    $fieldsToUpdate = [
                        ['field' => 'RECORD_STATUS', 'property' => 'hidden', 'value' => true, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_FIELD,],
                    ];
                    // hide buttons
                    $buttonstoHide[] = ['field' => 'manualresolve', 'hide' => true, 'identifier' => 'id', 'type' => EditorComponentFactory::TYPE_BUTTONS,];
                    $buttonstoHide[] = ['field' => 'manualreverse', 'hide' => true, 'identifier' => 'id', 'type' => EditorComponentFactory::TYPE_BUTTONS,];
                    $buttonstoHide[] = ['field' => 'post', 'hide' => true, 'identifier' => 'id', 'type' => EditorComponentFactory::TYPE_BUTTONS,];
                    $buttonstoHide[] = ['field' => 'reverse', 'hide' => true, 'identifier' => 'id', 'type' => EditorComponentFactory::TYPE_BUTTONS,];
                    $fieldsToUpdate[] = ['field' => 'resultstitle', 'property' => 'title', 'value' => 'IA.RESULTS', 'identifier' => 'id', 'type' => null,];

                    break;
            }
        }


        // show/hide record# and drag and drop columns
        if (empty($obj['COGS_CLOSEDJE_INFO']))
        {
            $fieldsToUpdate[] = ['field' => 'results', 'property' => 'hideLineNo', 'value' => true, 'identifier' => 'id', 'type' => null,];
            $fieldsToUpdate[] = ['field' => 'results', 'property' => 'noDragDrop', 'value' => true, 'identifier' => 'id', 'type' => null,];
        }
        else
        {
            $fieldsToUpdate[] = ['field' => 'results', 'property' => 'hideLineNo', 'value' => false, 'identifier' => 'id', 'type' => null,];
            $fieldsToUpdate[] = ['field' => 'results', 'property' => 'noDragDrop', 'value' => false, 'identifier' => 'id', 'type' => null,];
        }

        // show/hide the not records message
        if (empty($obj['COGS_CLOSEDJE_INFO']) && !empty($obj['NORESULTSMESSAGE']))
        {
            $fieldsToUpdate[] = ['field' => 'NORESULTSMESSAGE', 'property' => 'hidden', 'value' => false, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_SECTION,];
        }
        else
        {
            $fieldsToUpdate[] = ['field' => 'NORESULTSMESSAGE', 'property' => 'hidden', 'value' => true, 'identifier' => 'path', 'type' => EditorComponentFactory::TYPE_SECTION,];
        }
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


        foreach ($buttonstoHide as $value)
        {
            // set the buttons to hide/show
            $buttonContainers = [];
            $view->findComponents([$value['identifier'] => $value['field']], $value['type'], $buttonContainers);

            foreach ($buttonContainers as $buttonContainer)
            {
                $buttons = $buttonContainer->getProperty('button');
                for ($i = 0; $i < count($buttons); $i++)
                {
                    if ($buttons[$i][$value['identifier']] == $value['field'])
                    {
                        $buttons[$i]['hidden'] = $value['hide'];
                        $buttonContainer->setProperty('button', $buttons);
                    }
                }
            }
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
        if (isSpecified($obj['ITEMDIMGROUPID']))
        {
            /* @var  ItemGroupManager $itemGroupManager */
            $itemGroupManager = Globals::$g->gManagerFactory->getManager('itemgroup');
            $itemMembers = $itemGroupManager->getGroupMembersById($obj['ITEMDIMGROUPID']);

            if (count($itemMembers['MEMBERIDS']) > 0)
            {
                $items = [];
                foreach ($itemMembers['MEMBERIDS'] as $item)
                {
                    list($itemid) = explode('--', $item);
                    $items[] = $itemid;
                }

                $filterstring['filters'][] = [
                    ['itemid', 'in', $items],
                ];
            }
        }
        else
        {
            if (isSpecified($obj['FROMITEMID']))
            {
                $fromItem = $obj['FROMITEMID'];
                $toItem = $obj['TOITEMID'];

                /* ----------------- Filters -------------------*/
                list($fromitemid) = explode('--', $fromItem);
                $fromitemid = $fromitemid ? isl_trim(isl_htmlspecialchars($fromitemid)) : VARCHAR2_MIN;
                list($toitemid) = explode('--', $toItem);
                $toitemid = $toitemid ? isl_trim(isl_htmlspecialchars($toitemid)) : VARCHAR2_MAX;

                if ($fromitemid != '' && $toitemid != '')
                {
                    $filterstring['filters'][] = [
                        ['itemid', '>= ', "$fromitemid"],
                        ['itemid', '<= ', "$toitemid"],
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
    private function setDateFilter(array &$obj, & $filterstring)
    {
        $ok = true;
        if (isSpecified($obj['FROMDATE']) && isSpecified($obj['TODATE']))
        {
            /* @var  ItemManager $itemManager */

            $fromDate = $obj['FROMDATE'];
            $toDate = $obj['TODATE'];

            /* ----------------- Date Filters -------------------*/
            // date filters
            if ($fromDate == '' && $toDate == '')
            {
                // not valid
            }
            else
            {
                $filterstring['filters'][] = [
                    ['asofdate', '>= ', "$fromDate"],
                    ['asofdate', '<= ', "$toDate"],
                ];
            }
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
            $toWarehouse = $obj['TOWAREHOUSEID'];

            /* ----------------- Warehouse Filters -------------------*/
            // warehouse filters
            if ($fromWarehouse == '' && $toWarehouse == '')
            {
            }
            else
            {
                list($fromWarehouseid) = explode('--', $fromWarehouse);
                $fromWarehouse = $fromWarehouseid ? isl_trim(isl_htmlspecialchars($fromWarehouseid)) : VARCHAR2_MIN;
                list($toWarehouseid) = explode('--', $toWarehouse);
                $toWarehouse = $toWarehouseid ? isl_trim(isl_htmlspecialchars($toWarehouseid)) : VARCHAR2_MAX;

                $filterstring['filters'][] = [
                    ['warehouseid', '>= ', "$fromWarehouse"],
                    ['warehouseid', '<= ', "$toWarehouse"],
                ];
            }
        }
        return $ok;
    }


    /**
     * @param array $obj
     * @param array $filterstring
     * @return bool
     */
    private function setLocationFilter(array &$obj, & $filterstring)
    {

        $ok = true;
        if (isSpecified($obj['LOCATIONID']))
        {
            $location = $obj['LOCATIONID'];
            list($location) = explode('--', $location);
            $location = $location ? isl_trim(isl_htmlspecialchars($location)) : VARCHAR2_MIN;

            /* -----------------  Filters -------------------*/
            //  filters

            $filterstring['filters'][] = [
                ['locationid', '= ', "$location"],
            ];
        }

        return $ok;
    }

    /**
     * @param array $obj
     * @param array $filterstring
     * @return bool
     */
    private function setCustomerFilter(array &$obj, & $filterstring)
    {

        $ok = true;
        if (isSpecified($obj['CUSTOMERID']))
        {
            $customer = $obj['CUSTOMERID'];
            list($customer) = explode('--', $customer);
            $customer = $customer ? isl_trim(isl_htmlspecialchars($customer)) : VARCHAR2_MIN;

            /* -----------------  Filters -------------------*/
            //  filters

            $filterstring['filters'][] = [
                ['document.entity', '=', "C" . $customer],
            ];
        }

        return $ok;
    }


    /**
     * @param array $obj
     * @param array $filterstring
     * @return bool
     */
    private function setNeedadjustmentFilter(array &$obj, & $filterstring)
    {
        $ok = true;
        $this->needsAdjustment = null;
        if (isSpecified($obj['NEEDSADJUSTMENT']))
        {
            $needadjustment = $obj['NEEDSADJUSTMENT'];

            $needadjustment = $needadjustment == 'true' ? "true" : "false";
            /* -----------------  Filters -------------------*/
            //  filters

            $filterstring['filters'][] = [
                ['NEEDSADJUSTMENT', '=', "$needadjustment"],
            ];
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

        $filterstring['orders'][] = ['ASOFDATE', 'asc'];
        $filterstring['orders'][] = ['DOCUMENTNAME', 'asc'];

        return $ok;
    }


    /**
     * @param float  $number
     * @param int $decimals
     * @param string $dec_point
     * @param string $thousands_sep
     * @return string
     */
    private function formatnumber($number, $decimals = -1, $dec_point = '.', $thousands_sep = ',')
    {
        if (is_null($number))
        {
            return '';
        }
        if ($number < 0)
        {
            // code inspection doesn't like -$number
            $number = 0.0 -($number);
            if ($decimals < 0)
            {
                // determine the number of decimals
                $decimals = $this->getRoundToDecimals($number);
            }
            $formattednumber = number_format($number, $decimals, $dec_point, $thousands_sep);
            // add parens for negative value display
            $formattednumber = '(' . $formattednumber . ')';
        }
        else
        {
            if ($decimals < 0)
            {
                $decimals = $this->getRoundToDecimals($number);
            }
            $formattednumber = number_format($number, $decimals, $dec_point, $thousands_sep);
        }
        return $formattednumber;
    }

    /**
     * @param float  $num
     * @return int
     */
    private function getRoundToDecimals($num)
    {
        // minimum of 2 decimal places
        $decimals = Util::getNumberOfDecimals($num);
        $decimals = ($decimals > 2) ? $decimals : 2;
        return $decimals;
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
        // automatic significat digits
        $roundto = -1;

        foreach ($snapshotData as $aRow)
        {
            $thisrow = [];

            $thisrow['RECORDNO'] = $aRow['RECORDNO'];
            $thisrow['COGSDATE'] = $aRow['ASOFDATE'];
            $thisrow['ITEM'] = $aRow['ITEMID'] . '--' . $aRow['ITEMNAME'];
            $thisrow['CUSTOMER'] = $aRow['CUSTOMERID'] . '--' . $aRow['CUSTOMERNAME'];
            $thisrow['WAREHOUSE'] = $aRow['WAREHOUSEID'] . '--' . $aRow['WAREHOUSENAME'];
            $thisrow['LOCATION'] = $aRow['LOCATIONID'] . '--' . $aRow['LOCATIONNAME'];
            $thisrow['EXISTINGCOGS'] = $this->formatnumber($aRow['CURRENTGLCOGS'], $roundto, '.', '');
            $thisrow['RECALCCOGS'] = $this->formatnumber($aRow['CURRENTCOST'], $roundto, '.', '');
            $thisrow['ADJUSTAMOUNT'] = $this->formatnumber($aRow['DIFFERENCE'], $roundto, '.', '');
            $thisrow['PREVIOUSADJUSTAMOUNT'] = $this->formatnumber($aRow['COGSRESOLVE_AMOUNT'], $roundto, '.', '');
            $thisrow['ADJUSTMENT_DATE'] = "";
            $thisrow['TRANSACTION'] = $aRow['DOCUMENTNAME'];
            $thisrow['POSTINGID'] = $aRow['POSTINGID'];
            $thisrow['LINENO'] = $aRow['LINENO'] + 1;

            $rec = $aRow['DOCHDRID'];
            // add javascript call here
            $urlrec = "'" . urlencode($rec) . "'";
            $op = GetOperationId('so/lists/sodocument/view');
            $jsMethodToCall = "handleTransactionLink($urlrec, $op)";
            $thisrow['TRANSACTION'] = "<a  style=\"color:blue\" href=\"#\" onclick=\" " . $jsMethodToCall . "\">" . $aRow['DOCHDRID'] . "</a>";

            // get gl record
            global $gManagerFactory;
            $glentryMgr = $gManagerFactory->getManager('glentry');

            if (is_null($aRow['COGSRESOLVE_GLENTRYKEY']))
            {
                $existingGLEntryRecord1 = null;
            }
            else
            {
                $params = [
                    'selects' => ['BATCHNO', 'BATCH_DATE', 'BATCHTITLE', 'GLBATCH.REFERENCENO', 'GLBATCH.BATCH_NO'],
                    'filters' => [
                        [
                            [
                                'recordno', '=', $aRow['COGSRESOLVE_GLENTRYKEY'],
                            ],
                        ],
                    ],
                ];

                $existingGLEntryRecord1 = $glentryMgr->GetList($params)[0];
            }
            // get entry records
            $rec = $existingGLEntryRecord1['BATCHNO'];
            $noValidAdjustment = false;
            if (empty($aRow['COGSRESOLVE_GLENTRYKEY']) || (empty($existingGLEntryRecord1)) || (empty($rec)))
            {
                // no valid record resolve reocrd
                $noValidAdjustment = true;
            }
            else
            {
                $thisrow['ADJUSTMENT_DATE'] = $existingGLEntryRecord1['BATCH_DATE'];
            }

            $statusvalue = 0;
            $statusvalue += ($aRow['NEEDSADJUSTMENT'] == 'true') ? 1 : 0;
            $statusvalue += ($aRow['MANUAL_ADJUSTMENT'] == 'true') ? 2 : 0;
            // get status text from combination of NEEDSADJUSTMENT and MANUALLYADJUSTED
            switch ($statusvalue)
            {
                case 0:
                    // adjustment = false, manual = false
                    $statusText = GT($this->textMap,'IA.COGSCLOSEDJE_POSTED');
                    // set adjustment transaction link

                    if ($noValidAdjustment)
                    {
                        // no transactin link
                        break;
                    }
                    $urlrec = "'" . urlencode($rec) . "'";
                    $op = GetOperationId('gl/lists/glbatch/view');

                    // add javascript call here
                    $jsMethodToCall = "handleaAjustmentLink($urlrec, $op)";

                    $transname = $existingGLEntryRecord1['REFERENCENO'] . ' - ' . $existingGLEntryRecord1['GLBATCH.BATCH_NO'];

                    $thisrow['ADJUSTMENT_TRANSACTION'] = "<a  style=\"color:blue\" href=\"#\" onclick=\" " . $jsMethodToCall . "\">" . $transname . "</a>";

                    break;

                case 1:
                    // adjustment = true, manual = false
                    $statusText = GT($this->textMap,'IA.RECOMMENDED');
                    // no transactin link
                    break;

                case 2:
                    // adjustment = false, manual = true
                    $statusText = GT($this->textMap,'IA.MANUALLY_ADJ');
                    // no transactin link
                    break;

                case 3:
                default:
                    // adjustment = true, manual = true
                    $statusText = GT($this->textMap,'IA.UNKNOWN_STATUS');
                    break;
            }
            $thisrow['RECORD_STATUS'] = $statusText;

            $orderingLineItems[] = $thisrow;
        }

        return $ok;
    }

    /**
     * @param array $obj
     * @return mixed
     */
    function getSelectedRow(&$obj)
    {
        $values['RECORDNO'] = [];
        $values['POSTINGID'] = [];
        $rowcount = 0;

        foreach ($obj['COGS_CLOSEDJE_INFO'] as $row)
        {
            if ($row['INCLUDED'] == 'true')
            {
                // record selected
                $values['RECORDNO'][] = $row['RECORDNO'];
                $values['POSTINGID'][] = $row['POSTINGID'];
                $rowcount++;
            }
        }
        // save count of rows
        $obj['NUMBEROFSELECTEDROWS'] = $rowcount;

        return $values;
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
     * @param array $_params
     * @return bool
     */
    public function handleManualresolveButton($_params)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $cogsclosedjeMgr = $gManagerFactory->getManager('cogsclosedje');

        $this->retrieveObjectFromView($_params, $obj);

        $values = $this->getSelectedRow($obj);
        $values['MANUAL_ADJUSTMENT'] = 'T';

        $ret = $cogsclosedjeMgr->setManualResolve($values);

        $this->processPreviewActionWithObj($obj);

        return $ret;
    }


    /**
     * @param array $_params
     * @return bool
     */
    public function handleManualreverseButton($_params)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $cogsclosedjeMgr = $gManagerFactory->getManager('cogsclosedje');


        $this->retrieveObjectFromView($_params, $obj);
        $values = $this->getSelectedRow($obj);

        $deleteId = [];
        $deleteId['MANUAL_ADJUSTMENT'] = 'F';

        for ($rowcount = 0; $rowcount < count($values['RECORDNO']); $rowcount++)
        {
            // reformat data
            $deleteId['RECORDNO'][] = $values['RECORDNO'][$rowcount] . '--' . $values['POSTINGID'][$rowcount];
        }

        $ret = $cogsclosedjeMgr->setManualResolve($deleteId);

        $this->processPreviewActionWithObj($obj);
        return $ret;
    }


    /**
     *  Handle the post button
     *
     * @param array $_params
     *
     * @return bool                 did it work?
     */
    public function handlePostButton($_params)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $cogsclosedjeMgr = $gManagerFactory->getManager('cogsclosedje');

        $this->retrieveObjectFromView($_params, $obj);
        $values = $this->getSelectedRow($obj);

        $values["POSTINGDATE"] = $obj['POSTINGDATE'];

        $validdate = $this->validatepostingdate($obj['POSTINGDATE']);
        if (!$validdate)
        {
            $ok   = false;
            $gErr = Globals::$g->gErr;
            $msg  = GT($this->textMap,'IA.POSTING_DATE_INVALID_ENTER_VALID_POSTING_DATE');
            $gErr->addIAError('INV-0995', __FILE__ . ':' . __LINE__, $msg, ['MESSAGE_VALUE'=>$msg]);
            // i18N::TODO - (Code Change Review).
            $this->SetMessage($msg);
            $cogsclosedjeMgr->commitStatus =
                [
                    'SUCCESS' => 0,
                    'FAIL'    => 0,
                    'TOTAL'   => 0,
                    'MESSAGE' => $msg,
                ];
        }
        else
        {
            $ok = $cogsclosedjeMgr->add($values);
        }
        $this->processPreviewActionWithObj($obj);
        return $ok;
    }


    /**
     * @param array $_params
     * @return bool
     */
    public function handleReverseButton($_params)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        /** @var CogsClosedJeManager $cogsclosedjeMgr */
        $cogsclosedjeMgr = $gManagerFactory->getManager('cogsclosedje');


        $this->retrieveObjectFromView($_params, $obj);
        $values = $this->getSelectedRow($obj);
        $deleteId = [];
        $deleteId['MANUAL_ADJUSTMENT'] = 'F';


        for ($rowcount = 0; $rowcount < count($values['RECORDNO']); $rowcount++)
        {
            // reformat data
            $deleteId['RECORDNO'][] = $values['RECORDNO'][$rowcount] . '--' . $values['POSTINGID'][$rowcount];
        }
        $ret = $cogsclosedjeMgr->Delete($deleteId['RECORDNO']);
        $this->processPreviewActionWithObj($obj);

        return $ret;
    }


    /**
     * I18N. Collection of tokens used primarily in JavaScript.
     *
     * @return string[]
     */
    protected function getFormTokens() : array
    {
        $this->textTokens[] = 'IA.ROWS_SELECTED_ON_THIS_PAGE';
        $this->textTokens[] = 'IA.NO_RESULT_FOR_SELECTED_FILTERS';
        return parent::getFormTokens();
    }
}

