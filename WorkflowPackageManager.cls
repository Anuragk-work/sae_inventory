<?
//=============================================================================
//
//	FILE:			WorkflowPackageManager.cls
//	AUTHOR:			SRAO
//
//	(C)2000, Intacct Corporation, All Rights Reserved
//
//	Intacct Corporation Proprietary Information.
//	This document contains trade secret data that belongs to Intacct 
//	corporation and is protected by the copyright laws. Information herein 
//	may not be used, copied or disclosed in whole or part without prior 
//	written consent from Intacct Corporation.
//
//=============================================================================

import('PackageManager');
include_once('XMLUtils.cls');
require_once('xmlutil.inc');
define('STANDARDOBJXMLFILE', "INVSTDOBJECTS.xml");

/**
 * This is a futuristic implementation where we want to manage the packages from the customerp package upload.
 *
 * Class WorkflowPackageManager
 */
class WorkflowPackageManager extends PackageManager {

    use PayrollWorkflowPackageManagerTrait;
    use SREWorkflowPackageManagerTrait;
    /**
     * @var array $wflDocIdTokens
     */
    public static $wflDocIdTokens = [
        'Sales Invoice'               => [ 'DOCID'       => 'IA.SO_WORKFLOW_SALES_INVOICE',
                                           'DESCRIPTION' => 'IA.SO_WORKFLOW_SALES_INVOICE' ],
        'Sales Credit Memo'           => [ 'DOCID'       => 'IA.SO_WORKFLOW_SALES_CREDIT_MEMO',
                                           'DESCRIPTION' => 'IA.SO_WORKFLOW_SALES_RETURN' ],
        'Sales Return'                => [ 'DOCID'       => 'IA.SO_WORKFLOW_SALES_RETURN',
                                           'DESCRIPTION' => 'IA.SO_WORKFLOW_SALES_RETURN' ],
        'Sales Order'                 => [ 'DOCID'       => 'IA.SO_WORKFLOW_SALES_ORDER',
                                           'DESCRIPTION' => 'IA.SO_WORKFLOW_SALES_ORDER' ],
        'Shipper'                     => [ 'DOCID'       => 'IA.SO_WORKFLOW_SHIPPER',
                                           'DESCRIPTION' => 'IA.SO_WORKFLOW_SHIPPER' ],
        'Sales Quote'                 => [ 'DOCID'       => 'IA.SO_WORKFLOW_SALES_QUOTE',
                                           'DESCRIPTION' => 'IA.SO_WORKFLOW_SALES_QUOTE' ],
        'Activation'                  => [ 'DOCID'       => 'IA.SO_WORKFLOW_ACTIVATION',
                                           'DESCRIPTION' => 'IA.SO_WORKFLOW_ACTIVATION' ],
        'Purchase Requisition'        => [ 'DOCID'       => 'IA.PO_WORKFLOW_PURCHASE_REQUISITION',
                                           'DESCRIPTION' => 'IA.PO_WORKFLOW_PURCHASE_REQUISITION' ],
        'Vendor Invoice'              => [ 'DOCID'       => 'IA.PO_WORKFLOW_VENDOR_INVOICE',
                                           'DESCRIPTION' => 'IA.PO_WORKFLOW_VENDOR_INVOICE' ],
        'Purchasing Debit Memo'       => [ 'DOCID'       => 'IA.PO_WORKFLOW_PURCHASING_DEBIT_MEMO',
                                           'DESCRIPTION' => 'IA.PO_WORKFLOW_PURCHASING_DEBIT_MEMO' ],
        'Purchase Order'              => [ 'DOCID'       => 'IA.PO_WORKFLOW_PURCHASE_ORDER',
                                           'DESCRIPTION' => 'IA.PO_WORKFLOW_PURCHASE_ORDER' ],
        'PO Return'                   => [ 'DOCID'       => 'IA.PO_WORKFLOW_PO_RETURN',
                                           'DESCRIPTION' => 'IA.PO_WORKFLOW_PO_RETURN' ],
        'PO Receiver'                 => [ 'DOCID'       => 'IA.PO_WORKFLOW_PO_RECEIVER',
                                           'DESCRIPTION' => 'IA.PO_WORKFLOW_PO_RECEIVER' ],
        'Inventory Transfer Out'      => [ 'DOCID'       => 'IA.INV_WORKFLOW_INV_TRANSFER_OUT',
                                           'DESCRIPTION' => 'IA.INV_WORKFLOW_INV_TRANSFER_OUT_DESCRIPTION' ],
        'Inventory Shipper'           => [ 'DOCID'       => 'IA.INV_WORKFLOW_INV_SHIPPER',
                                           'DESCRIPTION' => 'IA.INV_WORKFLOW_INV_SHIPPER_DESCRIPTION' ],
        'Adjustment Decrease Value'   => [ 'DOCID'       => 'IA.INV_WORKFLOW_ADJUSTMENT_DECREASE_VALUE',
                                           'DESCRIPTION' => 'IA.INV_WORKFLOW_ADJUSTMENT_DECREASE_VALUE_DESCRIPTION' ],
        'Adjustment Decrease'         => [ 'DOCID'       => 'IA.INV_WORKFLOW_ADJUSTMENT_DECREASE',
                                           'DESCRIPTION' => 'IA.INV_WORKFLOW_ADJUSTMENT_DECREASE_DESCRIPTION' ],
        'Inventory Scrap or Spoilage' => [ 'DOCID'       => 'IA.INV_WORKFLOW_INV_SCRAP_OR_SPOILAGE',
                                           'DESCRIPTION' => 'IA.INV_WORKFLOW_INV_SCRAP_OR_SPOILAGE_DESCRIPTION' ],
        'Inventory Damaged Goods'     => [ 'DOCID'       => 'IA.INV_WORKFLOW_INV_DAMAGED_GOODS',
                                           'DESCRIPTION' => 'IA.INV_WORKFLOW_INV_DAMAGED_GOODS_DESCRIPTION' ],
        'Beginning Balance'           => [ 'DOCID'       => 'IA.INV_WORKFLOW_BEGINNING_BALANCE',
                                           'DESCRIPTION' => 'IA.INV_WORKFLOW_BEGINNING_BALANCE_DESCRIPTION' ],
        'Adjustment Increase Value'   => [ 'DOCID'       => 'IA.INV_WORKFLOW_ADJUSTMENT_INCREASE_VALUE',
                                           'DESCRIPTION' => 'IA.INV_WORKFLOW_ADJUSTMENT_INCREASE_VALUE_DESCRIPTION' ],
        'Adjustment Increase'         => [ 'DOCID'       => 'IA.INV_WORKFLOW_ADJUSTMENT_INCREASE',
                                           'DESCRIPTION' => 'IA.INV_WORKFLOW_ADJUSTMENT_INCREASE_DESCRIPTION' ],
        'Inventory Transfer In'       => [ 'DOCID'       => 'IA.INV_WORKFLOW_INV_TRANSFER_IN',
                                           'DESCRIPTION' => 'IA.INV_WORKFLOW_INV_TRANSFER_IN_DESCRIPTION' ],
        'Inventory Receipt'           => [ 'DOCID'       => 'IA.INV_WORKFLOW_INV_RECEIPT',
                                           'DESCRIPTION' => 'IA.INV_WORKFLOW_INV_RECEIPT_DESCRIPTION' ],
    ];

    /**
     * @param array $params
     */
    public function __construct($params = array())
    {
        // !! Bypassing PackageManager::__construct.  Something stinks.
        EntityManager::__construct($params);

       $this->_source = "WORKFLOWPACKAGEMANAGER";
    }

    /**
     * @param string    $option
     * @param string    $module
     *
     * @return bool
     */
	public function InstallWorflowTemplate($option, $module) {
		global $gErr;
		
		$ok = $this->_QM->beginTrx($this->_source);
		
		if ($option == 'CUSTOM') {		 
    		global $_FILES;
        

	        $xmlFile = $_FILES['_obj__CUSTWORKFLOW']['tmp_name'];	        
			$fsize = $_FILES['_obj__CUSTWORKFLOW']['size'];
			

			$fp = fopen ($xmlFile,"r");
			$xml = fread($fp,$fsize);
			fclose($fp);
		
		} else {
			
			$xmlFile = isl_strtoupper($module . "_" .$option).".xml";			
			$xml = join('',file($xmlFile, 1));
			
		}
		
		$ok = $ok && ValidateXML($xml, 'CustomDefinitionWorkflow.xsd');
		
		if (!$ok) {
			$msg = "Validation of custom workflow file failed";
			$gErr->addError('INV-0955', __FILE__ . ':' . __LINE__, $msg, 'The workflow package is not a valid one', 'Please check for errors and upload a valid package');
			epp("$this->_source: Error: $msg");			
		}
		
		// If the basic SCM tables are not yet populated, do so.
		//$ok = $ok && CopyStandardSCMTables(GetMyCompany());
		
		if (!$this->InstallStandardSCMObjects($module)) {
			$msg = "Could not install the Standard Intacct Objects";
			$gErr->addError('INV-0956', __FILE__ . ':' . __LINE__, $msg);
			$ok = false;
		}

		
		$ok = $ok && $this->CreateDocParStructures($xml, $module);

		global $gManagerFactory;
		$setupMgr = $gManagerFactory->getManager($module . "setup");
		/** @var DocumentSetupManager $setupMgr */
		$ok = $ok && $setupMgr->SetDefaultSetupForModule();
				
		$ok = $ok && $this->_QM->commitTrx($this->_source);
		if (!$ok) {
			$msg = "Could not install workflow";
			$gErr->addError('INV-0957', __FILE__ . ':' . __LINE__, $msg);
			epp("$this->_source: Error: $msg");
			$this->_QM->rollbackTrx($this->_source);
		}
		
		return $ok;
	}

    /**
     * @param string    $xml
     * @param string    $module
     *
     * @return bool
     */
	public function CreateDocParStructures($xml, $module) {		
		$ok = true;
		global $gErr, $gManagerFactory;
		
		$xpath = self::GetDOMXPath($xml);
		
		$modNode = $this->getElementText($xpath, '//ROOT/MODULE');
		
		if ($modNode != isl_strtoupper($module)) {
			$msg = "The custom workflow package you are trying to upload is not valid for this module.";
			$gErr->addError('INV-0958', __FILE__ . ':' . __LINE__, $msg, "", "Please upload a valid workflow package");
			return false;	
		}

		$wrkflwobject['DOCPARS'] = self::GetObjectValuesFromXPath(
			$xpath, 'ROOT', 'DOCPARS',
			array('DOCPAR_RECALLS'),
			array('DOCPAR_INVGL', 'DOCPAR_PRGL', 'DOCPAR_TOTALS', 'DOCPAR_SUBTOTAL')
		);
		$wrkflwobject['DOCPAR_RECALLS']	= self::GetObjectValuesFromXPath($xpath,'DOCPAR','DOCPAR_RECALLS');
		$wrkflwobject['DOCNUMSEQUENCES'] = self::GetObjectValuesFromXPath($xpath,'DOCPAR','DOCNUMSEQUENCES');

		if (count($wrkflwobject['DOCPARS']) == 0) {
			$msg = "There are no custom transaction definitions in the custom workflow.";
			$gErr->addError('INV-0959', __FILE__ . ':' . __LINE__, $msg, "", "Please upload a valid workflow package");
			return false;
		}


		// Create the docpar sequence structures.
        /** @var SeqNumManager $seqMgr */
		$seqMgr = $gManagerFactory->getManager("seqnum");
        foreach ( $wrkflwobject['DOCNUMSEQUENCES'] as $obj) {
			$res = $seqMgr->Get($obj['TITLE']);
			if (!$res) {						
				$ok = $ok && $seqMgr->add($obj);
			}
		}
		
		//$existingDocPars = $docParMgr->GetList();
		// deactivate all existing docpars.
        /** @var DocumentSetupManager $subsMgr */
		$subsMgr = $gManagerFactory->getManager($module . 'setup');
		$_spiArray = array ( 'inv' => 'I', 'po' => 'P', 'so' => 'S');	
		$ok = $ok && $subsMgr->DocParSetStatus($_spiArray[$module],'F','ALL');
		
		// Create the docpar structures.
        /** @var DocumentParamsManager $docParMgr */
		$docParMgr = $gManagerFactory->getManager($module . "documentparams");

		// If the inventory service is not subscribe and applying the workflow
		// to the inventory module set the flag indicating that subscribing to
		// the inventory service process is initiated
		$modMgr = $gManagerFactory->getManager('modules');
		if ('inv' === $module && !$modMgr->isModuleSubscribed("7.INV")) {
			$docParMgr->setInitiateSubscribeToInventory(true);
		}

        foreach ( $wrkflwobject['DOCPARS'] as $obj) {

            //tokenize and use
            $tokenDocId = $obj['DOCID'];
            if ( Util::countOrZero(self::$wflDocIdTokens[$tokenDocId] ?? []) > 0 ) {
                //change DOCID and DESCRIPTION
                $obj['DOCID'] = I18N::getSingleToken(self::$wflDocIdTokens[$tokenDocId]['DOCID']);
                $obj['DESCRIPTION'] = I18N::getSingleToken(self::$wflDocIdTokens[$tokenDocId]['DESCRIPTION']);
            }

			$latestDocParKey = $docParMgr->getLatestVersionKey($obj['DOCID']);
			
			if ($latestDocParKey) {
				// the TD with the given name has already been stored in the DB.
				// Copy over from the existing one subtotals and two collections
				// of the GL account mappings.
				$obj['NOWARNING'] = true;
				$obj['RECORDNO'] = $latestDocParKey;

				// Read the latest
				$includeOwnObjects = $docParMgr->isIncludeOwnObjects();
				$docParMgr->setIncludeOwnObjects(true);
				$latestObj = $docParMgr->GetLatest($obj['DOCID']);
				$docParMgr->setIncludeOwnObjects($includeOwnObjects);

				$obj['DOCPAR_INVGL'] = self::trimOwnedObjectRecord($latestObj['DOCPAR_INVGL']);
				$obj['DOCPAR_PRGL'] = self::trimOwnedObjectRecord($latestObj['DOCPAR_PRGL']);
				$obj['DOCPAR_SUBTOTAL'] = self::trimOwnedObjectRecord($latestObj['DOCPAR_SUBTOTAL']);
				$obj['SHOW_TOTALS'] = $latestObj['SHOW_TOTALS'];

				$automaticallyGenerated = $docParMgr->isAutomaticallyGenerated();
				$docParMgr->setAutomaticallyGenerated(true);
				$obj['SYSTEM_GENERATED'] = true;
				$ok = $ok && $docParMgr->set($obj);
				$docParMgr->setAutomaticallyGenerated($automaticallyGenerated);

			} else {
				$automaticallyGenerated = $docParMgr->isAutomaticallyGenerated();
				$docParMgr->setAutomaticallyGenerated(true);
				$obj['SYSTEM_GENERATED'] = true;
				$ok = $ok && $docParMgr->add($obj);
				$docParMgr->setAutomaticallyGenerated($automaticallyGenerated);
			}
			
			global $gErr;
			if ($gErr->hasErrors()) {
                return false;
			}
		}

		// Remove the subscription-to-inventory-service-initiated flag from
		// the TD manager
		$docParMgr->setInitiateSubscribeToInventory(false);

		// Create the docrecall structures.
        /** @var DocRecallsManager $docRecallMgr */
		$docRecallMgr = $gManagerFactory->getManager($module . "docrecalls");
        foreach ( $wrkflwobject['DOCPAR_RECALLS'] as $obj) {
            if ( Util::countOrZero(self::$wflDocIdTokens[$obj['DOCID']] ?? []) > 0 ) {
                //change DOCID and RECDOCPAR as per the token value
                $obj['DOCID'] = I18N::getSingleToken(self::$wflDocIdTokens[$obj['DOCID']]['DOCID']);
                $obj['RECDOCPAR'] = I18N::getSingleToken(self::$wflDocIdTokens[$obj['RECDOCPAR']]['DOCID']);
            }
			$obj['DOCPAR'] = $docParMgr->getLatestVersionKey($obj['DOCID']);
			if (!$docRecallMgr->IsExists($obj)) {
				$ok = $ok && $docRecallMgr->add($obj);
			}
		}

		// Now, after installing the new workflow, we have to make sure the items of the company have proper default offset accounts tied to the new docpars.
		/** @var ItemManager $itemMgr */
        $itemMgr = $gManagerFactory->getManager("item");
		
		$filter = array(array(array('STATUS', '=', 'active')));
		$params = array('filters' => $filter);
		$params['selects'] = array("ITEMID");		
		$itemList = $itemMgr->GetList($params);

        foreach ( $itemList as $item) {
			$itemObj = $itemMgr->Get($item['ITEMID']);
			$ok = $ok && $itemMgr->UpsertDefaultItemOffsets($itemObj);
		}
		return $ok;
	}

    /**
     * @param string    $module
     *
     * @return bool
     */
    public function InstallStandardSCMObjects(/** @noinspection PhpUnusedParameterInspection */ $module): bool
    {
        $ok = $this->InstallInventoryTotals();

        $ok = $ok && $this->InstallBasePricelist();

        $ok = $ok && $this->InstallStandardUOMGroups();

        if (!$ok) {
            $msg = "Could not insert the default scm objects";
            Globals::$g->gErr->addError('INV-0960', __FILE__ . ':' . __LINE__, $msg);
        }

        return $ok;
    }

    /**
     * @return bool
     */
    private function InstallInventoryTotals(): bool
    {
        $ok = true;
        $xml = join('', file(STANDARDOBJXMLFILE, 1));
        $xpath = self::GetDOMXPath($xml);

        $stdICtotalsList = self::GetObjectValuesFromXPath($xpath, 'SCMOBJECTS', 'ICTOTALS');

        if (!$this->CheckIfValuesExists('ICTOTAL')) {
            $totalsMgr = Globals::$g->gManagerFactory->getManager("invtotal");
            if (count($stdICtotalsList ?? []) > 0) {
                foreach ($stdICtotalsList as $value) {
                    $ok = $ok && $totalsMgr->add($value);
                }
            }
        }

        if (!$ok) {
            Globals::$g->gErr->addError('INV-0267', __FILE__ . ':' . __LINE__,
                "The default inventory totals could not be created.",
                "",
                "Try subscribing to the application again or contact Sage Intacct support.");
        }

        return $ok;
    }

    /**
     * @return bool
     */
    public function InstallBasePricelist(): bool
    {
        $ok = true;
        $xml = join('', file(STANDARDOBJXMLFILE, 1));
        $xpath = self::GetDOMXPath($xml);

        $stdOEPriceList = self::GetObjectValuesFromXPath($xpath, 'SCMOBJECTS', 'OEPRCLSTS');

        $invPriceListMgr = Globals::$g->gManagerFactory->getManager("invpricelist");
        $queryparams = [
            'selects' => ['NAME'],
            'filters' => [
                [
                    ['CNY#', '=', GetMyCompany()],
                    ['NAME', '=', 'Base Price List'],
                ]
            ],
            'usemst' => true,
        ];

        $res = $invPriceListMgr->GetList($queryparams);
        if (count($res) == 0) {
            if (count($stdOEPriceList ?? []) > 0) {
                foreach ($stdOEPriceList as $value) {
                    $ok = $ok && $invPriceListMgr->add($value);
                }
            }
        }

        if (!$ok) {
            Globals::$g->gErr->addError('INV-0268', __FILE__ . ':' . __LINE__,
                "The default base price list could not be created.",
                "",
                "Try subscribing to the application again or contact Sage Intacct support.");
        }

        return $ok;
    }

    /**
     * @return bool
     */
    public function InstallStandardUOMGroups()
    {
        $ok = true;
        $xml = join('', file(STANDARDOBJXMLFILE, 1));
        $xpath = self::GetDOMXPath($xml);

        $stdUOMGroups = self::GetObjectValuesFromXPath($xpath, 'SCMOBJECTS', 'ICUOMGRPS', ['UOMS']);

        $uomMgr = Globals::$g->gManagerFactory->getManager("uom");
        $params['selects'] = ['NAME'];
        $uoms = $uomMgr->GetList($params);
        $uomNames = [];

        if (count($uoms ?? []) > 0) {
            foreach ($uoms as $uom) {
                $uomNames[] = ($uom['NAME_ORIG'] ?? $uom['NAME']);
            }
        }

        if (count($stdUOMGroups ?? []) > 0) {
            foreach ($stdUOMGroups as $value) {
                //Create only if the standard uom does not exist in the company
                if (!in_array($value['NAME'], $uomNames)) {
                    $ok = $ok && $uomMgr->add($value);
                }
            }
        }

        if (!$ok) {
            $msg = "The default UOM groups could not be created. Try subscribing to the application again or contact Sage Intacct support.";
            Globals::$g->gErr->addError('INV-0961', __FILE__ . ':' . __LINE__,
                "","",$msg);
        }

        return $ok;
    }

    /**
     * @param string    $object     table name
     *
     * @return bool
     */
	public function CheckIfValuesExists($object) {
		
		$qry = "select count(1) as reccou from $object where cny# = :1 and rownum = 1 ";
		$res = QueryResult(array($qry, GetMyCompany()));
		
		if ($res[0]['RECCOU'] > 0) { 
			return true;
		}
		
		return false;
	}

    /**
     * @param string    $xml
     *
     * @return bool|DOMXPath
     */
	protected static function GetDOMXPath($xml) {
		global $gErr;
		
		$domXml = loadXmlDom($xml,
								   DOMXML_LOAD_PARSING + //0
  								   DOMXML_LOAD_COMPLETE_ATTRS + //8
  								   DOMXML_LOAD_SUBSTITUTE_ENTITIES + //4
  								   DOMXML_LOAD_DONT_KEEP_BLANKS //16
  								   , $error);
  								   
		if (count($error) > 0) {
			eppp($error);
			$msg = "Could not load the xml DOM workflow";
			$gErr->addError('INV-0962', __FILE__ . ':' . __LINE__, $msg);
			return false;
		}
		
		return new DOMXPath($domXml);
	}

    /**
     * @param DOMXPath  $xpath
     * @param string    $root
     * @param string    $plural_object
     * @param array     $ignoreNodes
     * @param array     $includeExtraNodes
     *
     * @return array
     */
	protected static function GetObjectValuesFromXPath($xpath, $root, $plural_object, $ignoreNodes = array(), $includeExtraNodes = array()) {
		$finalArray = array();
		
		$objectsNode = $xpath->evaluate("//".$root."/".$plural_object);		
		
		foreach($objectsNode as $objectNode) {
			
			$objectFieldsNode = $objectNode->childNodes;
			foreach($objectFieldsNode as $fieldNode) {
				$fieldValue = array();			
				$propertyNodes = $fieldNode->childNodes;
								
				foreach($propertyNodes as $propertyNode) {
					$key = $propertyNode->nodeName;
					
					// This is for subentries structure. We could have used recursion here, but decided not to make it complicated anymore.
					if( $key == 'ENTRIES' || in_array($key, $includeExtraNodes)) {
						$entries = $propertyNode->childNodes;

						foreach($entries as $fieldNode) {
							$entryfieldVal = array();
							$fieldPropertyNodes = $fieldNode->childNodes;
							foreach($fieldPropertyNodes as $fieldPropertyNode) {
								$fieldKey = $fieldPropertyNode->nodeName;
								$fieldVal = $fieldPropertyNode->nodeValue;
								$entryfieldVal[$fieldKey] = $fieldVal;
							}
							$fieldValue[$key][] = $entryfieldVal;
						}

					} else {						
						$val = $propertyNode->nodeValue;					
						if (!in_array($key,$ignoreNodes)) {					
							$fieldValue[$key] = $val;
						}
					}
				}
				$finalArray[] = $fieldValue;	
			}			
		}		
		return $finalArray;
	}

    /**
     * @param string $module
     */
	public static function ExportDocParDefinitions($module) { 
		global $gManagerFactory;
		
		$docParMgr = $gManagerFactory->getManager($module . "documentparams");
		
		$filter = array(array(array('STATUS', '=', 'active')));
		$params = array('filters' => $filter);		
		$docparlist = $docParMgr->GetList($params);
		
		$docpars = array();
        foreach ( $docparlist as $docpar) {
			if (isset($docpar['RECORDNO'])) {
				$docparObj = $docParMgr->get($docpar['RECORDNO']);

				self::PrepareDocParValuesForExport($docparObj);
				
				self::PrepareDocParRecallValuesForExport($docparObj);				
				
				self::PrepareDocParTotalValuesForExport($docparObj);
				
				self::PrepareDocParSequenceValuesForExport($docparObj);
										
				$docpars[] = $docparObj;		
			}
		}
		$docdefinition['DOCPARS'] = $docpars;
		$docdefinition['MODULE'] = isl_strtoupper($module);
		
		$docparXML = XMLUtils::PHP2XMLStr($docdefinition);

		// Remove the assoc="T" from the XML Definition.
		$docparXML = str_replace(' assoc="T" ', '', $docparXML);
		
		$filename = 'sample_install_'.$module.'workflow.xml';
		
		header("Content-Disposition: attachment; filename=\"$filename\""); 		
		header ("Content-Type: text/xml; charset=" . isl_get_charset());
		echo "<?xml version='1.0' encoding=\"" . isl_get_charset() . "\"?>\n";	
		echo $docparXML;
		
		exit(0);		
	}

    /**
     * @param array $values
     */
	private static function PrepareDocParValuesForExport(&$values) {
		$ignoreAttributes = array('RECORDNO', 'DOCPARNO', 'DOCPAR');
		
		$exportObject = array();
		foreach ($values as $key => $value) {
			if (!in_array($key, $ignoreAttributes) && isset($value) && $value != '') {
				$exportObject[$key] = $value;
			}			
		}
		
		$values = $exportObject;
	}

    /**
     * @param array $values
     */
	private static function PrepareDocParRecallValuesForExport(&$values) {
		$ignoreAttributes = array('RECORDNO', 'DOCPAR');
		
		$docparRecallExportObject = array();
        foreach ( $values['DOCPAR_RECALLS'] as $docparrecall) {
			$exportObject = array();
			foreach ($docparrecall as $key => $value) {
				if (!in_array($key, $ignoreAttributes) && isset($value) && $value != '') {
					$exportObject[$key] = $value;
				}
			}
			$exportObject['DOCID'] = $values['DOCID'];
			$docparRecallExportObject[] = $exportObject;		
		}
		
		$values['DOCPAR_RECALLS'] = $docparRecallExportObject;
	}

    /**
     * @param array $values
     */
	private static function PrepareDocParTotalValuesForExport(&$values) {
		$ignoreAttributes = array('RECORDNO', 'DOCPARNO');
		
		$docparTotalExportObject = array();
        foreach ( $values['DOCPAR_TOTALS'] as $docparrecall) {
			$exportObject = array();
			foreach ($docparrecall as $key => $value) {
				if (!is_array($value) && !in_array($key, $ignoreAttributes) && isset($value) && $value != '') {
					$exportObject[$key] = $value;
				}
			}
			$exportObject['DOCID'] = $values['DOCID'];
			$docparTotalExportObject[] = $exportObject;	
		}
		
		$values['DOCPAR_TOTALS'] = $docparTotalExportObject;
	}

    /**
     * @param array $values
     */
	private static function PrepareDocParSequenceValuesForExport(&$values) {
		global $gManagerFactory;
		
        /** @var SeqNumManager $seqnumMgr */
		$seqnumMgr = $gManagerFactory->getManager("seqnum");
		
		if ($values['SEQUENCE'] && $values['SEQUENCE'] != '') {
			$values['DOCNUMSEQUENCES']['DOCNUMSEQUENCE'] = $seqnumMgr->Get($values['SEQUENCE']);
		}		 
	}

    /**
     * @param array $values
     *
     * @return array
     */
	private static function trimOwnedObjectRecord($values) {
		$ignoreAttributes = array('RECORDNO', 'DOCPARNO');
		
		$trimedObject = array();
        foreach ( $values as $value) {
            foreach ( $ignoreAttributes as $attribute) {
				unset($value[$attribute]);
			}
			$trimedObject[] = $value;
		}
		
		return $trimedObject;
	}
}


