<?php

/**
 * Manager for SCM Macro Resolve object
 * 
 * @author    Senthil <skumar@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

/**
 * Manager class for SCM Macro Resolve
 */
class SCMMacroResolveManager extends EntityManager
{

    private const localTokens = [
        'IA.SALES_DOCUMENT_ID',
        'IA.PURCHASING_DOCUMENT_ID',
        'IA.SALES_LINE_NO',
        'IA.PURCHASING_LINE_NO',
        'IA.SOURCE_TRANSACTION',
        'IA.LANDED_COST_TRANSACTION',
        'IA.INVENTORY_ADJUSTMENT_TRANSACTION'
    ];

    private ?array $textMap = null;

    /**
     * __construct     
     * 
     * @param array $params entitymanager param
     */
    public function __construct($params = array())
    {
        parent::__construct($params);
        $this->initTextMap();
    }

    private function initTextMap()
    {
        if ($this->textMap === null) {
            $this->textMap = I18N::getTokensForArray(I18N::tokenArrayToObjectArray(self::localTokens));
        }
    }

    /**
     * set fieldinfo based on macro name     
     * 
     * @param string  $macroName    macro name
     * @param bool $forTargetDoc fields for target docs
     * 
     * @return array field info
     */
    public function getMacroHistoryFields($macroName, $forTargetDoc=false)
    {
        $fieldInfo = $this->GetEntityInfoMap(); 
        $fieldInfo['WHENCREATED']['hidden'] = false;
        $fieldInfo['CREATEDBY']['hidden'] = false;
        
        switch ($macroName) {
            
            case SCMMacroManager::DROPSHIP : 
            case SCMMacroManager::BTO :
                $fieldInfo['SOURCEDOCID']['fullname'] = GT($this->textMap, 'IA.SALES_DOCUMENT_ID');
                $fieldInfo['TARGETDOCID']['fullname'] = GT($this->textMap, 'IA.PURCHASING_DOCUMENT_ID');
                $fieldInfo['SOURCELINENO']['fullname'] = GT($this->textMap, 'IA.SALES_LINE_NO');
                $fieldInfo['TARGETLINENO']['fullname'] = GT($this->textMap, 'IA.PURCHASING_LINE_NO');
                
                if ($forTargetDoc) {
                    $historyFields = array(
                        'WHENCREATED', 'CREATEDBYID',  'TARGETDOCID', 'TARGETLINENO', 'ITEMNAME', 'SOURCEDOCID', 
                        'SOURCELINENO'
                    );
                } else {
                    $historyFields = array(
                        'WHENCREATED', 'CREATEDBYID', 'SOURCEDOCID', 'SOURCELINENO', 'ITEMNAME', 'TARGETDOCID',
                        'TARGETLINENO'
                    );
                }
                break;
            case SCMMacroManager::LANDEDCOST :
            case SCMMacroManager::LCACTANDESTREV :
                $fieldInfo['LANDEDCOSTDOCHDRID']['fullname'] = GT($this->textMap, 'IA.SOURCE_TRANSACTION');
                $fieldInfo['SOURCEDOCID']['fullname'] = GT($this->textMap, 'IA.LANDED_COST_TRANSACTION');
                $fieldInfo['TARGETDOCID']['fullname'] = GT($this->textMap, 'IA.INVENTORY_ADJUSTMENT_TRANSACTION');
                $historyFields = array(
                    'LANDEDCOSTDOCHDRID', 'SOURCEDOCID', 'TARGETDOCID',
                );
                break;
            case SCMMacroManager::LCEST :
                $fieldInfo['SOURCEDOCID']['fullname'] = GT($this->textMap, 'IA.SOURCE_TRANSACTION');
                $fieldInfo['LANDEDCOSTDOCHDRID']['fullname'] = GT($this->textMap, 'IA.LANDED_COST_TRANSACTION');
                $fieldInfo['TARGETDOCID']['fullname'] = GT($this->textMap, 'IA.INVENTORY_ADJUSTMENT_TRANSACTION');
                $historyFields = array(
                    'SOURCEDOCID', 'TARGETDOCID',
                );
                break;
            default:
                if ($forTargetDoc) {
                    $historyFields = array(
                        'WHENCREATED', 'CREATEDBYID', 'TARGETDOCID', 'SOURCEDOCID'
                    );
                } else {
                    $historyFields = array(
                        'WHENCREATED', 'CREATEDBYID', 'SOURCEDOCID', 'TARGETDOCID'
                    );
                }
                break;
        }
        
        $fieldsToDisplay = array();
        foreach ($historyFields as $field) {
            $fieldsToDisplay[$field] = $fieldInfo[$field];
        }
        
        return $fieldsToDisplay;
    }
    
    /**
     * get macro history based on macro name     
     * 
     * @param string  $macroName    macro name
     * @param string  $docRecordNo  record no. of the document
     * @param bool $forTargetDoc fields for target docs
     * 
     * @return array|false history
     */
    public function getMacroHistory($macroName, $docRecordNo, $forTargetDoc=false)
    {
        if (!$docRecordNo) {
            return false;
        }

        switch ($macroName) {
            
            case SCMMacroManager::DROPSHIP :
                $history = $this->getDropShipHistory($docRecordNo, $forTargetDoc);
                break;
            case SCMMacroManager::BTO :
                $history = $this->getBTOHistory($docRecordNo, $forTargetDoc);
                break;
            case SCMMacroManager::LANDEDCOST :
                $history = $this->getLandedCostHistory($docRecordNo);
                break;
            case SCMMacroManager::LCACTANDESTREV :
                $history = $this->getLCActAndEstRevHistory($docRecordNo);
                break;
            case SCMMacroManager::LCEST :
                $history = $this->getLCEstHistory($docRecordNo);
                break;
            default:
                if ($forTargetDoc) {
                    $params = array(
                        'filters' => array(
                            array(
                                array('MACRONAME', '=', $macroName),
                                array('TARGETDOCKEY', '=', $docRecordNo),
                            )
                        ),
                        'orders' => array(
                            array('WHENCREATED', 'asc'), array('SOURCEDOCID', 'asc')
                        )
                    );
                } else {
                    $params = array(
                        'filters' => array(
                            array(
                                array('MACRONAME', '=', $macroName),
                                array('SOURCEDOCKEY', '=', $docRecordNo),
                            )
                        ),
                        'orders' => array(
                            array('WHENCREATED', 'asc'), array('TARGETDOCID', 'asc')
                        )
                    );
                }
                $results = $this->GetList($params);
                
                $targetDocKey = array();
                foreach($results as $key => $res) {
                    if ( isset($targetDocKey[$res['TARGETDOCKEY']]) ) {
                        unset($results[$key]);
                    }
                    $targetDocKey[$res['TARGETDOCKEY']] = 1;
                }
                
                $history = array_values($results);
                break;
        }
        
        return $history;
        
    }

    /**
     * get history for landed cost actual adjustment macro
     *
     * @param string  $docRecordNo  record no. of the document
     *
     * @return array|false history
     */
    private function getLandedCostHistory($docRecordNo)
    {
        $history = $this->getLandedCostMacroHistoryHelper($docRecordNo, SCMMacroManager::LANDEDCOST);
        $reversedHistory = [];
        $docParIds = [];
        foreach (array_reverse($history) as $hist) {
            $reversedHistory[] = $hist;
            $docParIds[$hist['TARGETDOCPARID']] = 1;
        }
        return (arrayCount($docParIds) == 1 && $docParIds[InvDocumentManager::LANDEDCOSTESTDOCTYPE] == 1)? $reversedHistory : $history;
    }

    /**
     * get history for landed cost estimate reversal and actual adjustment macro
     *
     * @param string  $docRecordNo  record no. of the document
     *
     * @return array|false history
     */
    private function getLCActAndEstRevHistory($docRecordNo)
    {
        $history = $this->getLandedCostMacroHistoryHelper($docRecordNo, SCMMacroManager::LCACTANDESTREV);
        return $history;
    }

    /**
     * get history for landed cost estimate adjustment macto
     *
     * @param string  $docRecordNo  record no. of the document
     *
     * @return array|false history
     */
    private function getLCEstHistory($docRecordNo)
    {
        $tempHist = $this->getLandedCostMacroHistoryHelper($docRecordNo, SCMMacroManager::LCEST);
        $history = Array();
        foreach ( array_reverse($tempHist) as $hist ) {
            $history[] = $hist;
        }
        return $history;
    }

    /**
     * get history for landed cost history with estimate reversal and actual adjustments
     *
     * @param string  $docRecordNo  record no. of the document
     * @param string  $macroName                             
     *
     * @return array|false history
     */
    private function getLandedCostMacroHistoryHelper($docRecordNo, $macroName)
    {
        $params = array(
            'filters' => array(
                array(
                    array('MACRONAME', '=', $macroName),
                    array('SOURCEDOCKEY', '=', $docRecordNo),
                )
            ),
            'orders' => array(
                array('SOURCELINENO', 'asc'),
                array('RECORDNO', 'desc'),
            )
        );
        $results = $this->GetList($params);

        $targetDocKey = array();
        foreach($results as $key => $res) {
            if ( isset($targetDocKey[$res['TARGETDOCKEY']]) ) {
                unset($results[$key]);
            }
            $targetDocKey[$res['TARGETDOCKEY']] = $res;
        }

        $history = array_values($results);
        return $history;
    }

    /**
     * get history for drop ship   
     *
     * @param string  $docRecordNo  record no. of the document
     * @param bool $forTargetDoc fields for target docs
     * 
     * @return array|false history
     */    
    private function getDropShipHistory($docRecordNo, $forTargetDoc)
    {
        if (!$docRecordNo) {
            return false;
        }
        
        if ($forTargetDoc) {
            $params = array(
                'filters' => array(
                    array(
                        array('MACRONAME', '=', SCMMacroManager::DROPSHIP),
                        array('TARGETDOCKEY', '=', $docRecordNo),
                    )
                ),
                'orders' => array(
                    array('TARGETLINENO', 'asc'),
                    array('WHENCREATED', 'asc'),
                    array('SOURCEDOCID', 'asc'),
                    array('SOURCELINENO', 'asc')
                ),
            );
        } else {
            $params = array(
                'filters' => array(
                    array(
                        array('MACRONAME', '=', SCMMacroManager::DROPSHIP),
                        array('SOURCEDOCKEY', '=', $docRecordNo),
                    )
                ),
                'orders' => array(
                    array('SOURCELINENO', 'asc'),
                    array('WHENCREATED', 'asc'),
                    array('TARGETDOCID', 'asc'),
                    array('TARGETLINENO', 'asc')
                ),
            );
        }

        $history = $this->GetList($params);
        return $history;
    }
    
    /**
     * get history for BTO
     *
     * @param string  $docRecordNo  record no. of the document
     * @param bool $forTargetDoc fields for target docs
     * 
     * @return array|false history
     */    
    private function getBTOHistory($docRecordNo, $forTargetDoc)
    {
        if (!$docRecordNo) {
            return false;
        }
        
        if ($forTargetDoc) {
            $params = array(
                'filters' => array(
                    array(
                        array('MACRONAME', '=', SCMMacroManager::BTO),
                        array('TARGETDOCKEY', '=', $docRecordNo),
                    )
                ),
                'orders' => array(
                    array('TARGETLINENO', 'asc'),
                    array('WHENCREATED', 'asc'),
                    array('SOURCEDOCID', 'asc'),
                    array('SOURCELINENO', 'asc')
                ),
            );
        } else {
            $params = array(
                'filters' => array(
                    array(
                        array('MACRONAME', '=', SCMMacroManager::BTO),
                        array('SOURCEDOCKEY', '=', $docRecordNo),
                    )
                ),
                'orders' => array(
                    array('SOURCELINENO', 'asc'),
                    array('WHENCREATED', 'asc'),
                    array('TARGETDOCID', 'asc'),
                    array('TARGETLINENO', 'asc')
                ),
            );
        }

        $history = $this->GetList($params);
        return $history;
    }


}

