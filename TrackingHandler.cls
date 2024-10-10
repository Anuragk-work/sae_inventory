<?php

/**
 *	FILE: TrackingHandler.cls
 *	AUTHOR: Sudeendra Rao
 *	DESCRIPTION:
 *
 *	(C) 2000, Intacct Corporation, All Rights Reserved
 *
 *	This document contains trade secret data that belongs to Intacct
 *  Corporation and is protected by the copyright laws.  Information
 *	herein may not be used, copied or disclosed in whole or in part
 *	without prior written consent from Intacct Corporation.
 */


require_once('util.inc');
require_once('scm_util.inc');


/**
 * @author
 * @access       public
 */
class TrackingHandler {

    const  NO_BIN_ID_TOKEN = 'IA.NO_BIN_ID';

    const TRACK_EMPTY_FIELD = "___EMPTY___";  // when you want a NULL value, use this (will someone use this accidentally?  Maybe!

    /** @var array $_binTrackingDetails*/
    var $_binTrackingDetails = array();
    /* @var array $_serialTrackingDetails */
    var $_serialTrackingDetails = array();
    /* @var array $_lotTrackingDetails */
    var $_lotTrackingDetails = array();
    /** @var array $_sourceChildTrackingDetailsMap*/
    var $_sourceChildTrackingDetailsMap = array();

    /** @var array $_trackParams*/
    var $_trackParams = array();
    /** @var array $_itemsRawCache*/
    var $_itemsRawCache = array();

    /**
     * @var array $_aisleCache*/
    var $_aisleCache = array();
    /**
     * @var array $_rowCache*/
    var $_rowCache = array();
    /** @var array $_binCache*/
    var $_binCache = array();
    /** @var array $_whaeARBcache*/
    var $_whaeARBcache = array();
    /** @var array $_serialMaskCache*/
    var $_serialMaskCache = array();
    /** @var array $_duplicateSerialNos*/
    var $_duplicateSerialNos = array();
    /** @var array $_duplicateLotNos*/
    var $_duplicateLotNos = array();
    /** @var string $_action*/
    var $_action;


    /**
     * @param array $params
     */
    function __construct($params) {
		$this->_action = $params['ACTION'] !='' ? $params['ACTION'] : CREATE_ACTION;
	}


    /**
     * @param array $values
     */
    function PrepItemsCache($values){
		$gManagerFactory = Globals::$g->gManagerFactory;
		$itemMgr = $gManagerFactory->getManager('item');
		$itemsArr = array();

        foreach( $values['ENTRIES'] as $entry){
			if(isset($entry['ITEMID']) && !in_array($entry['ITEMID'], $itemsArr, true)) {
				$itemsArr[] = $entry['ITEMID'];
			}
			// Prepare ItemsCache
            foreach( $entry['ITEMDETAILS'] as $itementry){
				if(isset($itementry['ITEMID']) && !in_array($itementry['ITEMID'], $itemsArr, true)) {
					$itemsArr[] = $itementry['ITEMID'];
				}
			}
		}

		$this->_itemsRawCache = $itemMgr->GetItemsRawCache($itemsArr, true);
	}

    /**
     * @param string $kitItemID
     */
    function PrepKitComponentDetails($kitItemID){
		$gManagerFactory = Globals::$g->gManagerFactory;
        $itemMgr = $gManagerFactory->getManager('item');
		$itemComponentMgr = $gManagerFactory->getManager('itemcomponent');
		$kitItem = &$this->_itemsRawCache[$kitItemID];
		$hasTrackingEnabledItem = false ;
        $itemsArr = [];

		if($kitItem) {
			// get Kit component info
			$kitParams = array('filters' => array(array(array('ITEMID', '=', $kitItemID))));
			$kitComponents = $itemComponentMgr->GetList($kitParams);

            foreach( $kitComponents as $component) {
                $componentItemID = $component['COMPONENTKEY'];
                //
                // check if kit has any items(components) enabled for tracking
                $isComponentTracked = $this->isItemEnabledForTracking($componentItemID);
                $hasTrackingEnabledItem = $hasTrackingEnabledItem || $isComponentTracked;
                $component['ISSERIALIZED'] = $isComponentTracked;
                $kitItem['COMPONENT_INFO'][$componentItemID] = $component;

            	if(array_key_exists($componentItemID, $this->_itemsRawCache)){
            		continue;
				}
                $itemsArr[] = $component['COMPONENTKEY'];
            }
            // this is used in validating/process the tracking data later
            $kitItem['HASTRACKING_ENABLED_COMPONENTS'] = $hasTrackingEnabledItem;

            if( (!empty($itemsArr))){
                $kitComponentsCache = $itemMgr->GetItemsRawCache($itemsArr, true);
                foreach ($kitComponentsCache as $kCompKey => $kComponent){
                    $this->_itemsRawCache[$kCompKey] = $kComponent;
                }
			}
		}
	}

    /**
     * @param array $values
     *
     * @return bool
     */
    function PrepTrackingEntries(&$values){
		$ok = true;
		$this->_duplicateSerialNos = array();
		$this->_duplicateLotNos = array();
        $salePurTrans = $values['_DOCPAR']['SALE_PUR_TRANS'];

        foreach( $values['ENTRIES'] as $key => &$entry) {
            if ( !isset($entry['TRACKINGENTRIES'])) {
                $values['ENTRIES'][$key]['TRACKINGENTRIES'] = [];
            }
			$parentItemID = $entry['ITEMID'];
			$parentItem = $this->_itemsRawCache[$parentItemID];

			$lno = $entry['LINE_NO'];
            if ( $parentItem['ITEMTYPE'] == 'K'
                 || ( StkitDocumentManager::isStockableKitComponentTrackingEnabled()
                      && $parentItem['ITEMTYPE'] == 'SK'
                      && ( $values['DOCPARID'] == StkitDocumentManager::DISKIT
                           || $values['DOCPARID'] == StkitDocumentManager::BUILDKIT ) ) ) {
				$this->PrepKitComponentDetails($parentItemID);
			}
            //
            // prepare the tracking entries only if the document is affecting ONHand Quantity / Quantity & Value.
			// now we allow the ONHand Value documents too. but its not mandatory
            // check if the document need tracking info, else throw error
			$ok = $ok && $this->checkForTrackingData($entry);

			$trackQuantity = 0;
			$kitTrackQuantity = 0;
			$componentTrackQuantity = 0;

            foreach ($entry['TRACKINGENTRIES'] as $trackKey => &$trackEntry) {
                $restAPIOperation = strtolower($trackEntry['ia::operation'] ?? 'none');
                if (strcmp($restAPIOperation, 'delete') === 0) {
                    // Being deleted via the REST API; remove from further consideration
                    unset($entry['TRACKINGENTRIES'][$trackKey]);
                    continue;
                } else if (strcmp($restAPIOperation, 'patch') === 0) {
                    // Being updated via the REST API; sync the quantities based on API input
                    $trackEntry['TRACK_QUANTITY'] = $trackEntry['QUANTITY'];
                }
                if ($parentItem['ITEMTYPE'] == 'K') {
                    $ok = $ok && $this->PrepKitTrackingDetails($entry, $trackEntry);
                } else if ( $parentItem['ITEMTYPE'] == 'SK' && $values['DOCPARID'] == StkitDocumentManager::BUILDKIT
                            && StkitDocumentManager::isStockableKitComponentTrackingEnabled()
                            && (!empty($trackEntry['COMPONENTID']) || !empty($trackEntry['KITCOMPONENTID'])) ) {
                    // This is a stockable kit component and tracking is enabled.
                    $trackEntry['COMPONENTID'] = $trackEntry['KITCOMPONENTID'] ?? $trackEntry['COMPONENTID'];
                    $ok = $ok && $this->PrepKitTrackingDetails($entry, $trackEntry);
                } else if ( ! StkitDocumentManager::isStockableKitComponentTrackingEnabled()
                            || $values['DOCPARID'] != StkitDocumentManager::DISKIT ) {
                    $trackEntry['ITEMID'] = $parentItemID;
                }
                $trackEntry['ITEMLINENO'] = $lno;
                /*
                 * Only Stockable Kit level tracking should be validated here, and only during build
                 * transactions, so skip any component-level tracking specifications.
                 */
                if ( ! StkitDocumentManager::isStockableKitComponentTrackingEnabled()
                     || $values['DOCPARID'] != 'Build Kits'
                     || ! isset($trackEntry['COMPONENTID']) ) {
                    // prepare & validate (basic validations)
                    $ok = $ok && $this->PrepSerialTracking($entry, $trackEntry);
                    $ok = $ok
                          && $this->PrepBinTracking($entry, $trackEntry, $this->isInboundQuantity($values['_DOCPAR']));
                    $ok = $ok && $this->PrepLotTracking($entry, $trackEntry);
                    $ok = $ok && $this->PrepExpirationTracking($entry, $trackEntry);
                }
                /*
                 * However, for tracked components, we must still populate the binkey in tracking details
                 * for later consumption, as well as ensuring expirationdate specification when required.
                 */
                if ( StkitDocumentManager::isStockableKitComponentTrackingEnabled()
                     && $values['DOCPARID'] == 'Build Kits'
                     && isset($trackEntry['COMPONENTID']) ) {
                    if ( $this->isItemEnabledForTracking($trackEntry['COMPONENTID'], BINNO_ENABLED) ) {
                        $ok = $ok && $this->PrepBinTracking($entry, $trackEntry, $this->isInboundQuantity($values['_DOCPAR']));
                    }
                    if ( $this->isItemEnabledForTracking($trackEntry['COMPONENTID'], EXPIRATION_ENABLED) ) {
                        $ok = $ok && $this->PrepExpirationTracking($entry, $trackEntry);
                    }
                }

                $trackEntry['SALE_PUR_TRANS'] = $salePurTrans;
                $trackQuantity += is_numeric($trackEntry['QUANTITY']) ? $trackEntry['QUANTITY'] : 0;
                if ( StkitDocumentManager::isStockableKitComponentTrackingEnabled()
                     && ( ( $values['DOCPARID'] == StkitDocumentManager::BUILDKIT && empty($trackEntry['COMPONENTID']) )
                          || ( $values['DOCPARID'] == StkitDocumentManager::DISKIT
                               && $entry['ITEMID'] == $trackEntry['ITEMID'] ) ) ) {
                    $kitTrackQuantity += is_numeric($trackEntry['QUANTITY']) ? $trackEntry['QUANTITY'] : 0;
                } else {
                    $componentTrackQuantity += is_numeric($trackEntry['QUANTITY']) ? $trackEntry['QUANTITY'] : 0;
                }
            }

            $ok = $ok
                  && $this->ValidateTrackQuantity($entry, $trackQuantity, ( ( $values['BACKORDER'] ?? 'No' ) == 'Yes' ),
                                                  $kitTrackQuantity, $componentTrackQuantity, $values['DOCPARID']);
		}

		return $ok;
	}

    /**
     * Does this transaction increase quantity?
     *
     * @param array $docpar Current document attributes
     *
     * @return bool True if this transaction increases quantity and is not a return, false otherwise
     */
    private function isInboundQuantity($docpar)
    {
        return ( $docpar['UPDATES_INV'] == "Quantity and Value" || $docpar['UPDATES_INV'] == "Quantity" )
               && $docpar['IN_OUT'] == "Increase"
               && $docpar['CATEGORY'] != 'Return';
    }

    /**
     * @param array $entry
     * @param int   $trackQuantity
     * @param bool  $backorder          is this a back order?
     * @param int   $kitTrackQuantity
     * @param int   $componentTrackQuantity
     * @param string $docparid
     *
     * @return bool
     */
    function ValidateTrackQuantity(&$entry, $trackQuantity, $backorder, $kitTrackQuantity, $componentTrackQuantity,
                                   $docparid)
    {
        $gErr = Globals::$g->gErr;
        $trackParams = $this->_trackParams;

        // true if any of the tracking options is set to true for the item
        $trackingInfoEnabled_forItem = $this->isItemEnabledForTracking($entry['ITEMID']);
        $lineEntryQuantity = $entry['QUANTITY'];
        if ( StkitDocumentManager::isStockableKitComponentTrackingEnabled()
             && ( $docparid == StkitDocumentManager::BUILDKIT
                  || $docparid == StkitDocumentManager::DISKIT )
             && $componentTrackQuantity != 0 ) {
            /*
             * Tracking may be specified for *both* SKs and components during build and disassemble kit transactions.
             * We only care to validate the SK level quantities here for builds, and component level for disassemblies.
             */
            if ( $docparid == StkitDocumentManager::BUILDKIT ) {
                $qtydiff = ibcsub($lineEntryQuantity, $kitTrackQuantity, ItemManager::BASEUNITPRECISION);
            } else {
                $componentQtyRequired = 0;
                foreach ($this->_itemsRawCache[$entry['ITEMID']]['COMPONENT_INFO'] as $componentId => $componentInfo) {
                    if ($componentInfo['ISSERIALIZED']) {
                        $kitQuantity =
                            ibcmul($entry['QUANTITY'], $componentInfo['QUANTITY'], ItemManager::BASEUNITPRECISION);
                        $componentQtyRequired =
                            ibcadd($componentQtyRequired, $kitQuantity, ItemManager::BASEUNITPRECISION);
                    }
                }
                $componentQtydiff = ibcsub($componentQtyRequired, $componentTrackQuantity, ItemManager::BASEUNITPRECISION);
                $entryQtyDiff = ibcsub($lineEntryQuantity, $kitTrackQuantity, ItemManager::BASEUNITPRECISION);
                $qtydiff = ibcadd(abs($componentQtydiff), abs($entryQtyDiff), ItemManager::BASEUNITPRECISION);
            }
        } else {
            $qtydiff = ibcsub($lineEntryQuantity, $trackQuantity, ItemManager::BASEUNITPRECISION);
        }

        $validateQuantity = $trackParams['INV_TRACK_PREF_ENABLED']
            && $trackParams['AFFECTS_ONHAND']
            && $trackingInfoEnabled_forItem
            && ($qtydiff != 0)
            && !$trackParams['ISINVVALUEONLY'];

        //Check components for correct value for kits
        $ok = $this->validateKitComponentsQuantity($entry);

        if ($ok) {
            // if this is a backorder and we partially converted so the line item quantity is LESS THAN
            // the track quantity, lets just adjust the track quantity if we can
            if ($validateQuantity && ($qtydiff < 0) && $backorder) {
                $reduceQuantity = -((int)$qtydiff);
                foreach( $entry['TRACKINGENTRIES'] as $key => $trackEntry) {
                    if ((int)$trackEntry['QUANTITY'] > $reduceQuantity) {
                        $entry['TRACKINGENTRIES'][$key]['QUANTITY'] = (int)$trackEntry['QUANTITY'] - $reduceQuantity;
                        $reduceQuantity = 0;
                    } else {    // this tracking entry is LESS THAN or equal to the reduced quantity
                        $reduceQuantity -= (int)$trackEntry['QUANTITY'];
                        $entry['TRACKINGENTRIES'] = array_splice($entry['TRACKINGENTRIES'], $key, 1);   // remove this entry
                    }
                    if ($reduceQuantity == 0) {
                        break;
                    }
                }

                // did we find the right amount?
                if ($reduceQuantity == 0) {
                    $validateQuantity = false;
                }
            }

            // If tracking info not present, error out only when and
            if ($validateQuantity) {
                $entryLineNo = ibcadd($entry['LINENO'], '1', 0, false);
                if ($entry['UNITFACTOR'] == '1') {
                    if($this->_trackParams['MOD'] == 'so'){
                        $msg = sprintf('For item \'%1$s\' on line %2$s, enter the tracking details. Then, try again',
                                                               $entry['ITEMID'].'', $entryLineNo .'');
                        $msgPlaceholder = ['ENTRY_ITEMID' => $entry['ITEMID'], 'ENTRY_LINENO' => $entryLineNo];
                        $errorCode = 'INV-1077';
                    }else{
                        $msg = "Make sure the quantity in the line item field and the total quantity for the Serial, Lot, Bin information matches. Then try again.";
                        $msgPlaceholder = [];
                        $errorCode = 'INV-1079';
                    }
                } else {
                    if($this->_trackParams['MOD'] == 'so'){
                        $msg = sprintf('For item \‘%1$s\’ on line %2$s, enter quantities in the tracking information section that match the quantity in the line item field. The quantities in the tracking information section are always in the base unit.',
                                                               $entry['ITEMID'].'',  $entryLineNo .'');
                        $msgPlaceholder = ['ENTRY_ITEMID' => $entry['ITEMID'], 'ENTRY_LINENO' => $entryLineNo];
                        $errorCode = 'INV-1078';
                    }else{
                        $msg = "We've converted the quantity you entered in the line item into a base unit quantity of "
                                                           . "$lineEntryQuantity. Enter this number as the quantity in the Serial, Lot, "
                                                           . "and Bin Information screen.";
                        $msgPlaceholder = ['LINE_ENTRY_QUANTITY' => $lineEntryQuantity];
                        $errorCode = 'INV-1080';
                    }
                }

                /** @noinspection PhpUndefinedVariableInspection */
                if($this->_trackParams['MOD'] == 'so'){
                    $headerMsg = 'Serial, lot, or bin tracking information';
                    $headerPlaceholder = [];
                }else{
                    $bcAddValue = bcadd($entry['LINENO'], '1', 0);
                    $headerMsg = "For item " .$entry['ITEMID'] ." on Line " .$bcAddValue .", the tracking information is not valid.";
                    $headerPlaceholder = ['ENTRY_ITEMID' => $entry['ITEMID'], 'KEY' => $bcAddValue];
                }
                $gErr->addIAError($errorCode, __FILE__ . ':' . __LINE__, 'Unable to save Document', [], $headerMsg, $headerPlaceholder, $msg, $msgPlaceholder);
                //I18N::TODO (code change review)
                $ok = false;
            }
        }

        return $ok;
    }


    /**
     * Method to validate kit components quantity for SO module only. Any other modules will return true.
     *
     * @param array $entry
     *
     * @return bool
     */
    private function validateKitComponentsQuantity(&$entry)
    {
        $ok = true;

        //We just return true and don't need to validate if any of the following is true
        //-Module is not SO
        //-This entry does not affect QOH
        //-Line entry is not tying to a kit,
        if ( ($this->_trackParams['MOD'] != 'so'
            || $this->_trackParams['AFFECTS_ONHAND_QTY'] != true
            || $entry['ITEMTYPE'] != 'K')
             && ( ! StkitDocumentManager::isStockableKitComponentTrackingEnabled()
                  || Request::$r->_dt != 'Build Kits' ) ) {
            return $ok;
        }

        $quantity = $entry['QUANTITY'];
        $components = [];
        // find what is needed

        $gManagerFactory = Globals::$g->gManagerFactory;
        $itemmgr     = $gManagerFactory->getManager('item');


        foreach ($entry['ITEMDETAILS'] ?? [] as $itemdetail) {
            $qtyneeded = $quantity * $itemdetail['QUANTITY'];
            $itemname = $itemdetail['ITEMID'];

            $item = $itemmgr->get($itemname);
            $nonTrackingPseudoAllocated = 0;
            // see if this is a tracking item
            if ( !(
                ($item['ENABLE_BINS'] == 'true') ||
                ($item['ENABLE_LOT_CATEGORY'] == 'true') ||
                ($item['ENABLE_SERIALNO'] == 'true') ||
                ($item['ENABLE_EXPIRATION'] == 'true')
            )
            ) {
                // fake allocation to make the checking code easier
                $nonTrackingPseudoAllocated = $qtyneeded;
            }

            $components [$itemname] = $components [$itemname] ?? ['quantityRequired' => 0, 'quantityAllocated' => 0];
            $components [$itemname]['quantityRequired'] += $qtyneeded;
            $components [$itemname]['quantityAllocated'] += $nonTrackingPseudoAllocated;
        }

        // find what has been allocated
        foreach ($entry['TRACKINGENTRIES'] ?? [] as $tracking) {
            if ( StkitDocumentManager::isStockableKitComponentTrackingEnabled() && Request::$r->_dt == 'Build Kits'
                 && ! isset($tracking['COMPONENTID']) ) {
                // This is a build kit transaction, and this tracking specification refers to a SK, not a component
                continue;
            }
            $qty = $tracking['QUANTITY'];
            $itemname = $tracking['COMPONENTID'];
            $components [$itemname] = $components [$itemname] ?? ['quantityRequired' => 0, 'quantityAllocated' => 0];
            $components [$itemname]['quantityAllocated'] += $qty;
        }

        // see if the allocated and required match
        foreach ($components as $itemname=> $component) {
            if (ibccomp($component ['quantityAllocated'] , $component ['quantityRequired']) !=0) {
                // error
                $entryLineNo = ibcadd($entry['L_NO'], '1', 0, false);
                $msg =  sprintf('For kit component item \'%1$s\' on Line %2$s, make sure the total quantity in the Serial, Lot, Bin information matches the quantity in the line item field. The expected quantity is %3$s, but the actual quantity is %4$s. The quantities in the Serial, Lot, Bin information section are always in the base unit.',
                                $itemname.'', $entryLineNo .'', $component['quantityRequired'].'', $component['quantityAllocated'].'');
                $gErr = Globals::$g->gErr;
                $gErr->addIAError(
                    'INV-1081', __FILE__ . ':' . __LINE__,
                    'The kit component tracking information is not valid.', [],
                    '', [],
                    $msg, ['ITEMNAME' => $itemname, 'ENTRY_L_NO' => $entryLineNo, 'COMPONENT_QUANTITY_REQUIRED' => $component['quantityRequired'], 'COMPONENT_QUANTITY_ALLOCATED' => $component['quantityAllocated']]
                );

                $ok = false;
            }
        }

        return $ok;
    }

    /**
     * @param array $entry
     *
     * @return bool
     */
	function checkForTrackingData(&$entry)
    {
        $gErr = Globals::$g->gErr;
        $trackParams = $this->_trackParams;
        $ok = true;

        $itemID = $entry['ITEMID'];
        $itemInfo = $this->_itemsRawCache[$itemID];

		if($itemInfo['ITEMTYPE'] == 'K'){
            $itemEnabledforTracking = $itemInfo['HASTRACKING_ENABLED_COMPONENTS'];
        } else if ( ($itemInfo['ITEMTYPE'] == 'SK')
                    && ( StkitDocumentManager::isStockableKitTrackingEnabled()
                         || StkitDocumentManager::isStockableKitComponentTrackingEnabled() ) ) {
            $itemEnabledforTracking =
                $this->isItemEnabledForTracking($itemID) || $itemInfo['HASTRACKING_ENABLED_COMPONENTS'];
		}else{
            $itemEnabledforTracking = $this->isItemEnabledForTracking($itemID);
		}

		//
		// throw error if TRACKINGENTRIES are provided though it is not required.
		// from CSV TRACKINGENTRIES is always set for each line entry, but values may be null
		// same from XML
		// need to check all the tracking elements for the data in the TRACKINGENTRIES array
		if((!empty($entry['TRACKINGENTRIES'])) ){
			foreach($entry['TRACKINGENTRIES'] as $key=>$tEntry) {

                if(is_array($tEntry)) {
                    //We need to check for empty markers on the bin and blank it out as it's init in ICTransferEditor::cleanTrackingEntries
                    //before getting onto saving to disk. We need to do this otherwise $hasTrackingData below thinks we have bin tracking data
                    //when we really don't and error out of saving.
                    if ($tEntry['BINID'] == I18N::getSingleToken(self::NO_BIN_ID_TOKEN)
                        || $tEntry['BINID'] == self::TRACK_EMPTY_FIELD) {
                        $tEntry['BINID'] = '';
                    }

                    $trackDetails = $tEntry['QUANTITY'] . $tEntry['SERIALNO'] . $tEntry['AISLEID'] . $tEntry['ROWID']
                                    . $tEntry['BINID'] . $tEntry['LOTNO'] . $tEntry['EXPIRATION'];
                    $hasTrackingData = strlen($trackDetails) > 0;

                    // if it is a Kit or Stockable Kit check if the component(s) are enabled for tracking info
                    if (($itemInfo['ITEMTYPE'] == 'K'
                         || (StkitDocumentManager::isStockableKitComponentTrackingEnabled()
                             && $itemInfo['ITEMTYPE'] == 'SK'))
                        && $tEntry['COMPONENTID'] != '') {
                        $itemEnabledforTracking = $this->isItemEnabledForTracking($tEntry['COMPONENTID']);
                    }
                }else{
                    //remove the invalid tracking entry
                    unset($entry['TRACKINGENTRIES'][$key]);
                    $hasTrackingData=false;
                }

                if($hasTrackingData) {
				//
                    // if Tracking data exists
                    // and if Document doesnt require the tracking data
                    // or the Item / item component is not eanbled for tracking info
                    if ( !$itemEnabledforTracking) {
                        $lno = $entry['LINENO'] + 1;
                        $msg = "Tracking information not required for item  '" . $entry['ITEMID'] . "' in Line# " . ($lno) . ". Please remove the tracking details and try again";
                        $gErr->addIAError(
                            'INV-1021', __FILE__ . ':' . __LINE__,
                            "Unable to save document - Invalid Tracking Information provided", [],
                            $msg, ['ENTRY_ITEMID' => $entry['ITEMID'], 'LNO' => $lno]
                         );
                        $ok = false;
                        break;
                    }

                    if ($trackParams['ISINVVALUEONLY']) {
                        $lno = $entry['LINENO'] + 1;
                        $msg = "Inventory document affecting On Hand Value only can't be created with tracking details. Please remove the tracking details for item '" . $entry['ITEMID'] . "' in Line# " . ($lno) . " and try again.";
                        $gErr->addIAError(
                            'INV-1022', __FILE__ . ':' . __LINE__,
                            "Unable to save document - Invalid Tracking Information provided", [],
                            $msg, ['ENTRY_ITEMID' => $entry['ITEMID'], 'LNO' => $lno]
                        );
                        $ok = false;
                        break;
                     }
                    // Added this check since through CSV import the customer can import the quantity that is non numeric. PHP 8.1 ticket 163857
                    if ($itemEnabledforTracking && !is_numeric($tEntry['QUANTITY'])) {
                        $lno = $entry['LINENO'] + 1;
                        $msg = "Enter an numeric value for the tracking quantity for '" . $entry['ITEMID'] . "' in Line# " . ($lno) . "";
                        $gErr->addIAError(
                            'INV-1023', __FILE__ . ':' . __LINE__,
                            "Unable to save document - Invalid Tracking Information provided", [],
                            $msg, ['ENTRY_ITEMID' => $entry['ITEMID'], 'LNO' => $lno]
                        );
                        $ok = false;
                        break;
                    }
                }
			}
		}
		// Only check for tracking information if the item quantity is not null or 0.
		else if($itemEnabledforTracking && $trackParams['AFFECTS_ONHAND_QTY'] && isset($entry["UIQTY"]) && $entry["UIQTY"] != '0') {
            $lno = $entry['LINENO']+1;
            if($itemInfo['ITEMTYPE'] == 'K') {
                $itemMsg = "kit components of item ";
            } else {
                $itemMsg = "item ";
            }
            /** @noinspection PhpUndefinedVariableInspection */
            $msg = "Enter tracking information for " .$itemMsg .$entry['ITEMID'] ." on Line " .$lno .", then try again.";
            $gErr->addIAError(
                'INV-1024', __FILE__ . ':' . __LINE__,
                "The tracking information is incomplete.", [],
                $msg, ['ITEM_MSG' => $itemMsg,'ENTRY_ITEMID' => $entry['ITEMID'], 'LNO' => $lno]
            );
            $ok = false;
		}

        return $ok;
	}


    /**
     * @param array $entry
     * @param array $trackEntry
     *
     * @return bool
     */
    function PrepKitTrackingDetails($entry, &$trackEntry){
		$gErr = Globals::$g->gErr;
		$ok = true;

		$kitItemID = $entry['ITEMID'];
		$kitItem = $this->_itemsRawCache[$kitItemID];
		$hasTrackingEnabledItems = $kitItem['HASTRACKING_ENABLED_COMPONENTS'];
		$lno = $entry['LINENO'];

		// required for kit components
		if(isset($trackEntry['COMPONENTID']) && $trackEntry['COMPONENTID'] != '') {
			// setting kit item id
			$trackEntry['KITITEMID'] = $kitItemID;
			// setting component item id. ITEMID is used in the processing logic not the COMPONENTID
			$trackEntry['ITEMID'] = $trackEntry['COMPONENTID'];
		}else{
			// throw error if component ID is missing
			if($hasTrackingEnabledItems) {
				$msg = " Component Item ID is required for Kit '".$kitItemID."' in Line# ".($lno+1).". Please provide Component Item ID and try again";
				$gErr->addIAError(
				    'INV-1025', __FILE__ . ':' . __LINE__,
				    "Unable to save document - Invalid Tracking Information provided", [],
				    $msg, ['KIT_ITEM' => $kitItemID, 'LNO' => ($lno+1)]
				);
				$ok = false;
			}
		}

		return $ok;
	}

    /**
     * @param array $entry
     * @param array $trackEntry
     *
     * @return bool
     */
    function PrepSerialTracking($entry, &$trackEntry) {
		$gErr = Globals::$g->gErr;
		$ok = true;

		$trackEntryItemID = $trackEntry['ITEMID'];
		$item = $this->_itemsRawCache[$trackEntryItemID];
		$isSerialTrackingEnabled = $item['ENABLESNO'] == 'T';
		$lno = $entry['LINENO'];
		$serialNo = $trackEntry['SERIALNO'];
		//
		// if serial tracking is not enabled
		if (!$isSerialTrackingEnabled) {
			// check if any Bin tracking data is provided if item is not enabled for Serial tracking.
			// from XML & CSV there might be tracking data submitted accidentally.
			// if there is any tracking data provided throw error. This is system requirement.
			if ($serialNo != '') {
				$msg = "Serial tracking information not required for item  '".$trackEntryItemID."' in Line# ".($lno+1).". Please remove the tracking details and try again";
				$gErr->addIAError(
				    'INV-1026', __FILE__ . ':' . __LINE__,
				    "Unable to save document - Invalid Tracking Information provided", [],
				    $msg, ['TRACK_ENTRY_ITEM' => $trackEntryItemID, 'LNO' => ($lno+1)]
				);
				$ok = false;
			}
		}
		//
		// if serial tracking is enabled
		if ($ok && $isSerialTrackingEnabled) {

            // is the passed number one?
            $isOne = function($n) {
                $n = $n + 0;    // force it to be numeric
                return ($n == 1); //flex compare to support float numbers
            };

			// Quantity is always 1
			// throw error if Quantity is not 1.
            if (!is_numeric($trackEntry['QUANTITY']) || !$isOne($trackEntry['QUANTITY'])) {
                $msg = "Quantity should be 1 for item '".$trackEntryItemID."' in Line# ".($lno+1)." which is enabled for Serial Number tracking. Please change the Quantity and try again";
                $gErr->addIAError(
                    'INV-1027', __FILE__ . ':' . __LINE__,
                    "Unable to save document - Invalid Tracking Information provided", [],
                    $msg, ['TRACK_ENTRY_ITEM' => $trackEntryItemID, 'LNO' => ($lno+1)]
                );
                $ok = false;
            }

			// check if the serialnumber is provided
			if ($serialNo == '') {
				$msg = " Serial tracking information not provided for item  '".$trackEntryItemID."' in Line# ".($lno+1).". Please provide the tracking details and try again";
				$gErr->addIAError(
				    'INV-1028', __FILE__ . ':' . __LINE__,
				    "Unable to save document - Invalid Tracking Information provided", [],
				    $msg, ['TRACK_ENTRY_ITEM' => $trackEntryItemID, 'LNO' => ($lno+1)]
				);
				$ok = false;
			}

			// check for the serial mask if the serial mask is set for the item
			if ($item['SERIALMASKKEY'] != '') {
				$serialMaskDetails = $this->_serialMaskCache[$item['SERIALMASKKEY']];
				// validate for serial mask;
				if (is_array($serialMaskDetails)) {
                    $ok = $ok && $this->ValidateSerialMask($serialNo, $serialMaskDetails);
				}
			}

			// check for dupliczte serial numbers across all line items
			// using $this->_duplicateSerialNos to store serial numbers of all the line items
			if (array_key_exists($serialNo, ($this->_duplicateSerialNos[$trackEntryItemID])??[])) {
				$msg = "For item " .$trackEntryItemID ." on Line " .($lno+1) .", select a serial number other than " .$serialNo .". Then try again.";
				$gErr->addIAError(
				    'INV-1029', __FILE__ . ':' . __LINE__,
				    "The tracking information includes a duplicate serial number.", [],
				    $msg, ['TRACK_ENTRY_ITEM' => $trackEntryItemID, 'LNO' => ($lno+1), 'SERIAL_NO' => $serialNo]
				);
				$ok = false;
			}else{
				$this->_duplicateSerialNos[$trackEntryItemID][$serialNo] = array('ITEMID'=>$trackEntryItemID, 'LINENO'=> ($lno+1) );
			}
		}

		return $ok;
	}

    /**
     * @param array $entry
     * @param array $trackEntry
     * @param bool  $isInboundQuantity Quantity is increasing
     *
     * @return bool
     */
    function PrepBinTracking($entry, &$trackEntry, $isInboundQuantity){
		$gErr = Globals::$g->gErr;
		$ok = true;
		//eppp_p(__FUNCTION__." : ".__LINE__);

		$trackEntryItemID = $trackEntry['ITEMID'];
		$item = $this->_itemsRawCache[$trackEntryItemID];

		$itemWarehouseID = $entry['WAREHOUSE']['LOCATION_NO'];
		$isBinTrackingEnabled = $item['ENABLEBIN'] == 'T';
		$lno = $entry['LINENO'];

		$aisleID = $trackEntry['AISLEID'];
		$rowID = $trackEntry['ROWID'];
		$binID = $trackEntry['BINID'];
        $isNoBin = ($binID == I18N::getSingleToken(self::NO_BIN_ID_TOKEN)) || ($binID == self::TRACK_EMPTY_FIELD);
		if ($isNoBin) {
		    $binID = '';
        }
        $isToBin = isset($trackEntry['TO_BINID']) && ! empty($trackEntry['TO_BINID']);
        $toBin = $trackEntry['TO_BINID'];

		if (!$isBinTrackingEnabled) {
			// check if any Bin tracking data is provided if item is not enabled for Bin tracking.
			// from XML & CSV there might be tracking data submitted accidentally.
			// if there is any tracking data provided throw error. This is system requirement.
			$checkARBdata = $aisleID.$binID.$rowID;
			if(strlen($checkARBdata)>0){
				$msg = sprintf(" Bin tracking information not required for item  '%1s' in Line# %2s. Please remove the tracking details and try again", $trackEntryItemID, ($lno+1));
				$gErr->addIAError(
				    'INV-1030', __FILE__ . ':' . __LINE__,
				    "Unable to save document - Invalid Tracking Information provided", [],
				    $msg, ['TRACK_ENTRY_ITEM' => $trackEntryItemID, 'LNO' => ($lno+1)]
				);
				$ok = false;
			}
		}

		if($ok && $isBinTrackingEnabled) {
            $advanced = BinManager::areAdvanedBinsOn();
			//
			//Invalid Aisle
            $aisleKey = 0;
            $rowKey   = 0;
            if (!$advanced) {
                $whseAisles = $this->_whaeARBcache[$itemWarehouseID]['AISLES'];
                if ($ok && $aisleID != '') {
                    $ok = $ok && isset($whseAisles[$aisleID]);
                    if (!$ok) {
                        $msg = sprintf("Aisle %1s does not exist in Warehouse '%2s', at Line# %3s for item '%4s'", $aisleID, $itemWarehouseID, ($lno + 1), $trackEntryItemID);
                        $gErr->addIAError(
                            'INV-1031', __FILE__ . ':' . __LINE__,
                            $msg, ['AISLEID' => $aisleID, 'ITEM_WAREHOUSE' => $itemWarehouseID, 'LNO' => ($lno + 1), 'TRACK_ENTRY_ITEM' => $trackEntryItemID]
                        );
                    }
                    $trackEntry['AISLEKEY'] = $whseAisles[$aisleID]['RECORD#'];
                }

                //Invalid Row
                $whseRows = $this->_whaeARBcache[$itemWarehouseID]['ROWS'];
                if ($ok && $rowID != '') {
                    $ok = $ok && isset($whseRows[$rowID]);
                    if (!$ok) {
                        $msg = sprintf("Row %1s does not exist in Warehouse '%2s', at Line# %3s for item '%4s'", $rowID, $itemWarehouseID, ($lno + 1), $trackEntryItemID);
                        $gErr->addIAError(
                            'INV-1032', __FILE__ . ':' . __LINE__,
                            $msg, ['ROWID' => $rowID, 'ITEM_WAREHOUSE' => $itemWarehouseID, 'LNO' => ($lno + 1), 'TRACK_ENTRY_ITEM' => $trackEntryItemID]
                        );
                    }
                    $trackEntry['ROWKEY'] = $whseRows[$rowID]['RECORD#'];
                }
            } else {
                if ( $ok && StkitDocumentManager::isStockableKitTrackingEnabled() && $isInboundQuantity
                     && ( ( ! $isNoBin && $binID == '' )
                          || ( $isToBin && $toBin == '' ) ) ) {
                    $msg = "Bin tracking information is required for item  '" . $trackEntryItemID . "' in Line# "
                             . ( $lno + 1 ) . ". Please provide the tracking details and try again";
                    $gErr->addIAError(
                        'INV-1033', __FILE__ . ':' . __LINE__,
                        "Unable to save document - Invalid Tracking Information provided", [],
                        $msg, ['TRACK_ENTRY_ITEM' => $trackEntryItemID, 'LNO' => ($lno + 1)]
                    );
                    $ok = false;
                }
                $aisleKey = ($aisleID != '') ? ($this->_whaeARBcache[$itemWarehouseID]['AISLES'][$aisleID]['RECORD#'] ?? 0) : 0;
                $rowKey   = ($rowID   != '') ? ($this->_whaeARBcache[$itemWarehouseID]['ROWS'  ][$rowID  ]['RECORD#'] ?? 0) : 0;
            }
			//Invalid Bin
			$whseBins = $this->_whaeARBcache[$itemWarehouseID]['BINS'];
			if ($ok && $binID!='') {
				$ok = $ok && ($isNoBin || isset($whseBins[$binID]));
				if (!$ok) {
                    $msg = sprintf("Bin %1s does not exist in Warehouse '%2s', at Line# %3s for item '%4s'", $binID, $itemWarehouseID, ($lno + 1), $trackEntryItemID);
					$gErr->addIAError(
					    'INV-1034', __FILE__ . ':' . __LINE__,
					    $msg, ['BINID' => $binID, 'ITEM_WAREHOUSE' => $itemWarehouseID, 'LNO' => ($lno + 1), 'TRACK_ENTRY_ITEM' => $trackEntryItemID]
					);
				} else if ($advanced && ($aisleKey || $rowKey)) {
				    $aisleKeyInBin = $whseBins[$binID]['AISLEKEY'] ?? 0;
				    $rowKeyInBin   = $whseBins[$binID]['ROWKEY'  ] ?? 0;
				    if (($aisleKeyInBin != $aisleKey) || ($rowKeyInBin != $rowKey)) {
                        $msg = sprintf("Bin %1s does not match the Aisle ('%2s') or Row ('%3s') specified, at Line# %4s for item '%5s'", $binID, $aisleID, $rowID, ($lno + 1), $trackEntryItemID);
                        $gErr->addIAError(
                            'INV-1035', __FILE__ . ':' . __LINE__,
                            $msg, ['BINID' => $binID, 'AISLEID' => $aisleID, 'ROWID' => $rowID, 'LNO' => ($lno + 1), 'TRACK_ENTRY_ITEM' => $trackEntryItemID]
                        );
                        $ok = false;
                    }
                }
				$trackEntry['BINKEY'] = $isNoBin ? 0 : $whseBins[$binID]['RECORD#'];    // no-bin has no record#
			}
		}

		return $ok;
	}

    /**
     * @param array $entry
     * @param array $trackEntry
     *
     * @return bool
     */
    function PrepLotTracking($entry, &$trackEntry){
		$gErr = Globals::$g->gErr;
		$ok = true;

		$trackEntryItemID = $trackEntry['ITEMID'];
		$item = $this->_itemsRawCache[$trackEntryItemID];
		$isLotTrackingEnabled = $item['ENABLELOT'] == 'T';
		// line number of the item
		$lno = $entry['LINENO'];
		$lotNo = $trackEntry['LOTNO'];

		if(!$isLotTrackingEnabled){
			// check if any Lot tracking data is provided if item is not enabled for Lot tracking.
			// from XML & CSV there might be tracking data submitted accidentally.
			// if there is any tracking data provided throw error. This is system requirement.
			if($lotNo != ''){
				$msg = " Lot tracking information not required for item  '".$trackEntryItemID."' in Line# ".($lno+1).". Please remove the tracking details and try again";
				$gErr->addIAError(
				    'INV-1036', __FILE__ . ':' . __LINE__,
				    "Unable to save document - Invalid Tracking Information provided", [],
				    $msg, ['TRACK_ENTRY_ITEM' => $trackEntryItemID, 'LNO' => ($lno+1)]
				);
				$ok = false;
			}
		}

		if ($ok && $isLotTrackingEnabled) {
			if($lotNo=='') {
				$msg = " Lot tracking information is required for item  '".$trackEntryItemID."' in Line# ".($lno+1).". Please provide the tracking details and try again";
				$gErr->addIAError(
				    'INV-1037', __FILE__ . ':' . __LINE__,
				    "Unable to save document - Invalid Tracking Information provided", [],
				    $msg, ['TRACK_ENTRY_ITEM' => $trackEntryItemID, 'LNO' => ($lno+1)]
				);
				$ok = false;
			}

			// check for dupliczte Lot numbers across all line items
			// using $this->_duplicateLotNos to store Lot numbers of all the line items
			/*if(array_key_exists($lotNo, $this->_duplicateLotNos)){
				$dLno = $this->_duplicateLotNos[$lotNo]['LINENO'];
				$dItem = $this->_duplicateLotNos[$lotNo]['ITEMID'];
				$msg = "The Lot Number '".$lotNo."' in Line# ".($lno+1)." for the Item '" .$trackEntryItemID."' is already used in Line# ".($dLno)." for Item '".$dItem."'. Please select another Lot number";
				$gErr->addIAError(
                    'INV-1059',__FILE__.':'.__LINE__,
                    "Unable to save document - Duplicate Lot Number",[],
                    $msg, ['LOT_NO' => $lotNo, 'LNO_PLUS_1' => ($lno+1),
                            'TRACK_ENTRY_ITEM_ID' => $trackEntryItemID,
                            'D_LNO' => $dLno, 'D_ITEM' => $dItem]
                );
				$ok = false;
			}else{
				$this->_duplicateSerialNos[$lotNo] = array('ITEMID'=>$trackEntryItemID, 'LINENO'=> ($lno+1) );
			}*/
		}

		return $ok;
	}

    /**
     * @param array $entry
     * @param array $trackEntry
     *
     * @return bool
     */
    function PrepExpirationTracking($entry, $trackEntry){
		$gErr = Globals::$g->gErr;
		$ok = true;

		$trackEntryItemID = $trackEntry['ITEMID'];
		$item = $this->_itemsRawCache[$trackEntryItemID];
		$isExpirationTrackingEnabled = $item['ENABLEEXPIRATION'] == 'T';
		$expirationDate = $trackEntry['EXPIRATION'];
		$lno = $entry['LINENO'];

		if(!$isExpirationTrackingEnabled){
			// check if any Lot tracking data is provided if item is not enabled for Lot tracking.
			// from XML & CSV there might be tracking data submitted accidentally.
			// if there is any tracking data provided throw error. This is system requirement.
			if($expirationDate != ''){
				$msg = " Expiration tracking information not required for item  '".$trackEntryItemID."' in Line# ".($lno+1).". Please remove the tracking details and try again";
				$gErr->addIAError(
				    'INV-1038', __FILE__ . ':' . __LINE__,
				    "Unable to save document - Invalid Tracking Information provided", [],
				    $msg, ['TRACK_ENTRY_ITEM' => $trackEntryItemID, 'LNO' => ($lno+1)]
				);
				$ok = false;
			}
		}

		if ($ok && $isExpirationTrackingEnabled) {
			if($expirationDate=='') {
				$msg = " Expiration tracking information is required for item  '".$trackEntryItemID."' in Line# ".($lno+1).". Please provide the tracking details and try again";
				$gErr->addIAError(
				    'INV-1039', __FILE__ . ':' . __LINE__,
				    "Unable to save document - Invalid Tracking Information provided", [],
				    $msg, ['TRACK_ENTRY_ITEM' => $trackEntryItemID, 'LNO' => ($lno+1)]
				);
				$ok = false;
			}
		}

		// check for invalid $expirationDate
		// -- if $expirationDate < current date
		// -- if $expirationDate is not in correct format
		// -- need to discuss with PM : Erika

		return $ok;
	}

    /**
     * @param string $dochdrkey
     */
    function PrepParentChildTrackingEntriesMap($dochdrkey){
        //$trackParams = $this->_trackParams;
        // get the bin tracking details before updating parent and child documents
        //check whether enable serial/lot/bin tracking is enabled in inventory setup.
        //true if any of the tracking options is set to true in the INV module preferences
        //$trackingDetailsRequired = $trackParams['INV_TRACK_PREF_ENABLED'] && $trackParams['AFFECTS_ONHAND_QTY'] && $trackParams['UPDATES_INV'];
        //if ($trackingDetailsRequired) {
            $this->PrepParentChildBinTrackingDetailsMap($dochdrkey);
            $this->PrepParentChildSerialTrackingDetailsMap($dochdrkey);
            $this->PrepParentChildLotTrackingDetailsMap($dochdrkey);
        //}
	}

    /**
     * @param array $values
     *
     * @return bool
     */
    function PrepareTrackingInfo(&$values){
        $ok = true;
		$this->PrepTrackingParams($values);
        $ok = $ok && $this->PrepTrackingEntries($values);
        return $ok;
	}


    /**
     * @param array $values
     *
     * @return bool
     */
    function ProcessTrackingInfo(&$values) {

		$ok = true;
		$cny = GetMyCompany();

		//Initialize all the tracking parameters that will be widely used in different APIs in this TrackingHandler.
		//Note handlers are stateless objects and so, we should pass these $trackParams to caller APIs and we should
		// reinstantiate this array for this API.
		//$ok = $ok && $this->PrepareTrackingInfo($values);

		$trackParams = $this->_trackParams;
		$itemRawCache = $this->_itemsRawCache;
        $itemsHavingChildren = [];

        // Ref: EDIT_MODE_ITEM_CHANGE_VALIDATION
		// if the document is in edit mode
		// get all the items their serial numbers and the children
		if($trackParams['INV_TRACK_PREF_ENABLED'] && $this->_action == EDIT_ACTION){
			$ok = $ok && $this->CollectItemsWithChildren($itemsHavingChildren);
		}

        $isBuildKitTxn = ($values['DOCPARID']==StkitDocumentManager::BUILDKIT) ? true : false;
		$isDisassembleKitTxn = ($values['DOCPARID']==StkitDocumentManager::DISKIT) ? true : false;
        $isBuildDisassembleKitTxn = $isBuildKitTxn || $isDisassembleKitTxn;
		$isBegBal = ($values['DOCPARID']=='Beginning Balance') ? true : false;

        // now lets me more careful about specific scenarios....
        foreach($values['ENTRIES'] as $key=>$entry){
			if($isBuildDisassembleKitTxn){
                if (!StkitDocumentManager::isStockableKitTrackingEnabled()) {
                    $ok = $ok && $this->PrepareStockableAndDisassembleKits($values, $entry);
                } else {
                    $track = $entry['TRACKINGENTRIES'];
                    if ( ! $trackParams['ISINVVALUEONLY']
                         && $trackParams['INV_TRACK_PREF_ENABLED']
                         && ( $trackParams['AFFECTS_ONHAND_QTY'] || $trackParams['AFFECTS_ONHAND_VALUE_ONLY'] )
                         && ! $isDisassembleKitTxn
                         && ! empty($track)
                    ) {
                        if ( $this->isItemEnabledForTracking($entry['ITEMID']) ) {
                            $ok = $ok && $this->ValidateTrackingInfo($values, $entry, $track);
                            if ( ! $ok ) {
                                break;
                            }
                        }
                    }
                }
			}

			$itemdetails1 = array();
			foreach($entry['ITEMDETAILS'] as $itemkey=>$itementry){
				$item = $itemRawCache[$itementry['ITEMID']];
				//
				// true if any of the tracking options is set to true for the item
				$trackingInfoEnabled_forItem = $this->isItemEnabledForTracking($itementry['ITEMID']);

				// Added this and removing the kitqty multiplication in stkitdocmgr.findcost
				// added the $isBuildDisassembleKitTxn condition for stkit sales as we do not want this logic there
				if ($entry['ITEMTYPE']=='SK' && $values['DOCPARID']==StkitDocumentManager::BUILDKIT) {
					$values['ENTRIES'][$key]['ITEMDETAILS'][$itemkey]['QUANTITY'] = ibcmul($entry['QUANTITY'],$itementry['QUANTITY'], ItemManager::AVERAGE_COST_DECIMALS, true);
					$itementry['QUANTITY']=$values['ENTRIES'][$key]['ITEMDETAILS'][$itemkey]['QUANTITY'];
				}

				// if validation is true , fetch the data from the docentrytrack table and construct an array
				// For disassemble kits, do not get tracking info for components here since it seems this function
				// is only to verify that for tracked stkits/components, there is enough qty with trkg info avlbl
				// tracking info goes into itemdetails which goes into docentrycostkits - so we likely need components here
				// and in fact may need to remove stkititem from trackinfo
				if(
					!$trackParams['ISINVVALUEONLY']
					&& ($trackParams['AFFECTS_ONHAND_QTY'] || $trackParams['AFFECTS_ONHAND_VALUE_ONLY'])
				){
					//---### in edit mode and if it is a back order
					//---### check for edit mode. $trackParams['DOCMODE']
					$track = $this->GetTrackingEntries($entry, $itementry);

					// Get default item ARB locations for:ṇ
					// 1. tracked stockable kits lineitems (e.g. when doing InvIn/BegBal of a stkit item) or
					// 2. tracked non-stkits items in build/disassemble kit transactions
					// 3. beginning balance txns from CSV import
					if (($item['ITEMTYPE']=='SK' || ($entry['ITEMTYPE']=='SK' && $isBuildDisassembleKitTxn) || $isBegBal) &&
						$trackParams['INV_TRACK_PREF_ENABLED'] && $trackingInfoEnabled_forItem && $item['ENABLEBIN']=='T' ) {

                        if ( (!empty($track))) {
                            //
                            // ---### this call may not be required as we can get this info from $_whaeARBcache
                            $res = $this->GetDefaultAisleRowBinInfo($cny, $item['ITEMID'], $entry['WAREHOUSE']['LOCATION_NO']);
                            // Commenting the logic below so that we use components from any ARB in same whse when default ARB not specified for item
                            // --- ### need to recheck
                            $track = INTACCTarray_merge($track, $res);

                            // For stockable kits, there is no docentrycost entry, so only ARB gets populated. This can lead to
                            // a qty diff error at the end of ProcessTrackingInfo function - so set qty=lineitem qty here
                            if (!$track[0]['QUANTITY']) {
                                // This leads to doubling of qty for tracked items in build kit txns
                                $track[0]['QUANTITY'] = $itementry['QUANTITY'];
                            }
                        }

					}

				}


				// Do I need to include SK's here? -Vish - yes seems like multiplying kit qty by child qty
				// If i uncomment this - for disassemble kit components, the qty check at the end fails
				if ($entry['ITEMTYPE']=='K' /*|| $entry['ITEMTYPE']=='SK'*/){
					$values['ENTRIES'][$key]['ITEMDETAILS'][$itemkey]['QUANTITY'] = ibcmul($entry['QUANTITY'],$itementry['QUANTITY'], ItemManager::BASEUNITPRECISION, true);
				}else{
					$values['ENTRIES'][$key]['ITEMDETAILS'][$itemkey]['QUANTITY'] = $itementry['QUANTITY'];
				}

				if(!$trackParams['ISINVVALUEONLY'] 
					&& $trackParams['INV_TRACK_PREF_ENABLED'] 
					&& ($trackParams['AFFECTS_ONHAND_QTY'] || $trackParams['AFFECTS_ONHAND_VALUE_ONLY']) 
					&& !$isDisassembleKitTxn
                    && $trackingInfoEnabled_forItem
                    && !empty($track)
				){
				    $ok = $ok && $this->ValidateTrackingInfo($values, $entry, $track);
				}

				// $track -- Tracking details, required
				// $trackingInfoEnabled_forItem, -- can be prepared in the function. not required. prepared using $itementry['ITEMID']
				// $itementry, -- line item details entry (can be a kit component)
				// $item, -- item details item -- $itementry['ITEMID'] use itemcach to get the item in function. -- not required.
				// $entry, -- line item entry
				// $itemsHavingChildren, -- need to chage the way it is used. for not skip
				// $lineqty -- is passed by reference -- is required for further processing.
                /** @noinspection PhpUndefinedVariableInspection */
                $itemdetailsArr =
                    $this->PrepTrackingItemDetails($track, $trackingInfoEnabled_forItem, $itementry, $item, $entry,
                                                   $itemsHavingChildren, $lineqty, $isBuildKitTxn,
                                                   $isDisassembleKitTxn);
                $ok = $ok && $this->validateStockableKitComponents($entry, $itemdetailsArr, $isBuildKitTxn);

				// Keep appending the itemdetails array.
				$itemdetails1	= INTACCTarray_merge($itemdetails1, $itemdetailsArr);

			}

			$values['ENTRIES'][$key]['ITEMDETAILS']=$itemdetails1;
		}

		// Ref: EDIT_MODE_ITEM_CHANGE_VALIDATION
		// don't allow to change the item if
		//	-- items are enabled for serial tracking
		//	-- the serial numbers are already consumed
        if( $trackParams['INV_TRACK_PREF_ENABLED'] && (!empty($itemsHavingChildren))){
			$ok = $ok && $this->ValidateItemSerialInfo($itemsHavingChildren, $values['ENTRIES']);
		}

        // if fulfillment is enabled, do a more holistic approach to sales availability
        // given any RESERVED or ALLOCATED items.
        // TODO: This could be the model for all of the above since it does ONE set of queries
        //      rather than ONE set PER ENTRY.....
        if (($isBuildKitTxn || $trackParams['AFFECTS_ONHAND']) &&
            $trackParams['ISSALES'] &&
            InventoryWQOrderManager::featureEnabled(InventoryWQOrderManager::FEATURE_FLAG_ONLY)) {
            $ok = $ok && $this->validateReserveAllocteTracking($values);
        }
        return $ok;
	}


    /**
     * @param array $entry
     * @param array $itementry
     *
     * @return array
     */
	function GetTrackingEntries($entry, $itementry)
    {
        $trackParams = $this->_trackParams;
        $trackEntries = $entry['TRACKINGENTRIES'];

        if (!$trackParams['ISBACKORDER']) {
            if ($entry['ITEMTYPE'] == 'K') {
                $trackEntries = array();
                foreach ($entry['TRACKINGENTRIES'] as $tEntry) {
                    if ($tEntry['ITEMID'] == $itementry['ITEMID']) {
                        $trackEntries[] = $tEntry;
                    }
                }
            }
        }

        return $trackEntries;
    }

    /**
     * @param array $values
     * @param array $entry
     *
     * @return bool
     */
    function PrepareStockableAndDisassembleKits(&$values, &$entry){
        $gErr = Globals::$g->gErr;
        $cny = GetMyCompany();
        $ok = true;

        $trackParams = $this->_trackParams;

        // Get default item ARB locations for the stkit lineitem in the buildkit txn
        // Why do we need to call docentrycostmgr to get trkg enable info ($trackingInfoEnabled_forItem) when we already have it
        // May need to comment the condition for $isBuildDisassembleKitTxn to get tracking info for stkit sales orders if it does
        // not get handled in itemdetails
        if ($entry['ITEMTYPE']=='SK' && $trackParams['INV_TRACK_PREF_ENABLED'] && $entry['ENABLEBIN']=='T' ) {
            // For stockable kits where bin tracking is enabled, get default aisle/row/bin from icitemwhse
            // ---### this call is not required as we can get this info from $this->_whaeARBcache
            $res= $this->GetDefaultAisleRowBinInfo($cny,$entry['ITEMID'],$entry['WAREHOUSE']['LOCATION_NO']);
            if ($res) {
                /** @noinspection PhpUndefinedVariableInspection */
                $values['ENTRIES'][$key]['AISLEKEY']= $res[0]['AISLEKEY'];
                $values['ENTRIES'][$key]['ROWKEY']=$res[0]['ROWKEY'];
                $values['ENTRIES'][$key]['BINKEY']=$res[0]['BINKEY'];
                $values['ENTRIES'][$key]['AISLEID']=$res[0]['AISLEID'];
                $values['ENTRIES'][$key]['ROWID']=$res[0]['ROWID'];
                $values['ENTRIES'][$key]['BINID']=$res[0]['BINID'];
            } else {
                // Default aisle-row-bin needs to be available for an SK item for the whse specified in the document if bin tracking is enabled
                $msg = "Default aisle,row,bin information does not exist for Line# '".($entry['LINENO']+1)."' for the tracked stockable kit item '".
                    $entry['ITEMID']."' for warehouse '".$entry['WAREHOUSE']['LOCATION_NO']."'. Please specify that before attempting build kit.";
                $gErr->addIAError(
                    'INV-1040', __FILE__ . ':' . __LINE__,
                    "Unable to post document.", [],
                    $msg, ['ENTRY_LINENO' => ($entry['LINENO']+1), 'ENTRY_ITEMID' => $entry['ITEMID'], 'ENTRY_WAREHOUSE_LOCATION_NO' => $entry['WAREHOUSE']['LOCATION_NO']]
                );
                $ok=false;
            }
        }

        return $ok;
	}

    /**
     * @access    private
     *
     * @param array $values
     *
     */
	function PrepTrackingParams($values) {
		$gManagerFactory = Globals::$g->gManagerFactory;

		$params				= array();

		$params['IN_OUT']			= $values['_DOCPAR']['IN_OUT'];
		$params['SPI']				= $values['_DOCPAR']['SALE_PUR_TRANS'];
		$params['DOCID']			= $values['DOCID'];
		$params['RECALLED_ID']		= $values['CREATEDFROM'];
		$params['ISBACKORDER']		= ($values['BACKORDER'] == 'Yes') ? true : false;
		$params['WHENCREATED']		= $values['WHENCREATED'];
		$params['UPDATES_INV']		= $values['_DOCPAR']['UPDATES_INV'];
		$params['DOCPAR_RECORDKEY'] = $values['_DOCPAR']['RECORDKEY'];

		// Prep Various document types based on functionality.
		$params['ISPURCHASE_RETURN']= ($params['SPI']=='Purchase' && $params['IN_OUT']=='Decrease');
		$params['ISSALES_RETURN']	= ($params['SPI']=='Sale' && $params['IN_OUT']=='Increase');
		$params['ISSALES']			= (($params['SPI']=='Sale' || $params['SPI']=='Internal') && $params['IN_OUT']=='Decrease') ;
		$params['ISPURCHASE']		= (($params['SPI']=='Purchase' || $params['SPI']=='Internal') && $params['IN_OUT']=='Increase');

		//if in TD , totals are affeacting ONHAND qty then
		$docparTotal = $this->GetOnHAndTotal($values['_DOCPAR']);


		//$params['AFFECTS_ONHAND_QTY'] = $this->AffectsOnHAndQuantity($values['_DOCPAR']);
        //$params['AFFECTS_ONHAND_VALUE_ONLY'] = $this->AffectsOnHAndValueOnly($values['_DOCPAR']);
		$params['ISINVVALUEONLY']		= ($params['SPI']=='Internal' && $docparTotal == 'Value');
        $params['AFFECTS_ONHAND_QTY'] =  ($docparTotal == 'Quantity' || $docparTotal == 'Quantity & Value');
        $params['AFFECTS_ONHAND_VALUE'] =  ($docparTotal == 'Value' || $docparTotal == 'Quantity & Value');
        $params['AFFECTS_ONHAND_VALUE_ONLY'] =  $docparTotal == 'Value';
        $params['AFFECTS_ONHAND'] =  ($docparTotal == 'Quantity' || $docparTotal == 'Quantity & Value' || $docparTotal == 'Value');

		$mod			= $values['_mod'];
		$params['MOD']	= $mod;


		$docMgr	= $gManagerFactory->getManager($mod . 'document');
		//$params['ISRETURN'] = $docMgr->isReturnDocument($values['_DOCPAR']);

		global $kINVid;
		GetModulePreferences($kINVid,$prefs);

		// true if any of the tracking options is set to true in the INV module preferences
		$params['INV_TRACK_PREF_ENABLED'] = ($prefs['ENABLESERIAL']=='T' || $prefs['ENABLELOT']=='T' || $prefs['ENABLEBIN']=='T' || $prefs['ENABLE_EXPIRATION']=='T');

		//$params['DOCMODE']	= ($values['_do'] != '' ? $values['_do'] : 'create');
		//$params['DOCMODE']	= $this->_action;

		// The following is to append parent information into the
		$this->prepParentInfo($values, $params);

		//
		// prepare items raw cache
		$this->PrepItemsCache($values);
		//
        if($prefs["ENABLEBIN"] == 'T'){
		    // prepare aisle, row & bin cache
            if (BinManager::areAdvanedBinsOn() == false) {
                $this->PrepAllWarehouseAislesCache();
                $this->PrepAllWarehouseRowsCache();
            }
            $this->PrepAllWarehouseBinsCache();
		}
        if($prefs["ENABLESERIAL"] == 'T') {
            // prepare serialmask cache
            $this->PrepSerialMaskCache();
        }
		$this->_trackParams = $params;
	}

    /**
     * @param array $values
     * @param array $trackingParams
     */
    public function prepParentInfo($values, &$trackingParams)
    {
        // The following is to append parent information into the tracking params
        $source_dockeys = [];
        foreach ($values['ENTRIES'] as $key => $entry) {
            // collect all the source docdhrkeys
            $source_dockeys[] = $entry['SOURCE_DOCKEY'];
        }

        if (count($source_dockeys) <= 0) {
            return;
        }

        $source_dockeys = array_unique($source_dockeys);
        sort($source_dockeys);

        $qrySourceDocs = [];
        $qrySourceDocs[0] .= "SELECT dp.record#, dp.docid, dp.updinv, dh.record# source_dockey, dh.docid dochdrid,
                            DECODE(dp.in_out, 'I', 'Increase', 'O', 'Decrease') in_out,
                            DECODE(dp.updinv,'T','Quantity and Value','V','Value','Q','Quantity') affects_inventory
                            FROM docparmst dp
                            INNER JOIN dochdrmst dh ON dh.cny# = dp.cny# AND dh.docparkey = dp.record#
                            WHERE dp.cny# = :1";
        $qrySourceDocs[] = GetMyCompany();
        $qrySourceDocs = PrepINClauseStmt($qrySourceDocs, $source_dockeys, ' AND dh.record# ');
        $srcDocsResult = QueryResult($qrySourceDocs);

        if ($srcDocsResult !== false) {
            foreach ($srcDocsResult as $srcDoc) {
                $parentDocparTotal = $srcDoc['AFFECTS_INVENTORY'];
                $sourceDocKey = $srcDoc['SOURCE_DOCKEY'];

                $trackingParams['PARENTINFO'][$sourceDocKey] = [
                    'AFFECTS_ONHAND_QTY' => ($parentDocparTotal == 'Quantity'
                        || $parentDocparTotal == 'Quantity & Value'),
                    'AFFECTS_ONHAND_VALUE' => ($parentDocparTotal == 'Value'
                        || $parentDocparTotal == 'Quantity & Value'),
                    'AFFECTS_ONHAND_VALUE_ONLY' => ($parentDocparTotal == 'Value'),
                    'AFFECTS_ONHAND' => ($parentDocparTotal == 'Quantity'
                        || $parentDocparTotal == 'Quantity & Value'
                        || $parentDocparTotal == 'Value'),
                    'IN_OUT' => $srcDoc['IN_OUT'],
                ];
            }
        }
    }

    /**
     * @access    private
     *
     * @param array $itemsHavingChildren
     *
     * @return bool
     */
	function CollectItemsWithChildren(&$itemsHavingChildren) {
		// get the items having child
		foreach($this->_serialTrackingDetails as $iKey => $trackdetails){
			foreach($trackdetails as $trackdetail){
				if(isset($trackdetail['CHILD_DETAILS'])){
					$itemsHavingChildren[$iKey][$trackdetail['SERIALNO']] = $trackdetail['ITEMLINENO'];
				}
			}
		}
		foreach($this->_lotTrackingDetails as $iKey => $trackdetails){
			foreach($trackdetails as $trackdetail){
				if(isset($trackdetail['CHILD_DETAILS'])){
					$itemsHavingChildren[$iKey][$trackdetail['LOTNO']] = $trackdetail['ITEMLINENO'];
				}
			}
		}
		foreach($this->_binTrackingDetails as $iKey => $trackdetails){
			foreach($trackdetails as $tKey => $trackdetail){
				if(isset($trackdetail['CHILD_DETAILS'])){
					$itemsHavingChildren[$iKey][$tKey] = $trackdetail['ITEMLINENO'];
				}
			}
		}

		return true;
	}


    /**
     * @access    private
     *
     * @param array $itemsHavingChildren
     * @param array $entries
     *
     * @return bool
     */
	function ValidateItemSerialInfo($itemsHavingChildren, $entries) {
		$gErr = Globals::$g->gErr;
		$ok = true;

		foreach($itemsHavingChildren as $iKey => $child){
			if( ((!empty($child)))){
				$GetTracktype = $this->_itemsRawCache[$iKey];

				$arrkeys = array_keys($child);
				$serial_lot_bin = $arrkeys[0];
				$arrvals = array_values($child);
				$LineNo = $arrvals[0];
				$newItem = $entries[$LineNo]['ITEMID'];
				$errorCode = 'INV-1082';
				$placeholder = [];

				if ($GetTracktype['ENABLESNO']=='T'){
					$msg = "Serial Number '".$serial_lot_bin."' assigned to item '".$iKey."' has already been consumed. Can't change the Item '".$iKey."' in Line#". ($LineNo+1);
					$errorCode = 'INV-1083';
					$placeholder = ['SERIAL_LOT_BIN' => $serial_lot_bin, 'I_KEY' => $iKey, 'LINE_NO' => ($LineNo+1)];
				}else if($GetTracktype['ENABLELOT']=='T'){
					$msg = "Lot Number '".$serial_lot_bin."' assigned to item '".$iKey."' has already been consumed. Can't change the Item '".$iKey."' in Line#". ($LineNo+1);
					$errorCode = 'INV-1084';
					$placeholder = ['SERIAL_LOT_BIN' => $serial_lot_bin, 'I_KEY' => $iKey, 'LINE_NO' => ($LineNo+1)];
				}elseif($GetTracktype['ENABLEBIN']=='T'){
                    list($LineNo, $aisleid, $rowid, $binid) = explode("|", $serial_lot_bin);
					$binMsg = $aisleid;
					$binMsg = ($rowid!='') ? ($binMsg!='' ? $binMsg ." >> ".$rowid : $rowid) : $binMsg;
					$binMsg = ($binid!='') ? ($binMsg!='' ? $binMsg ." >> ".$binid : $binid) : $binMsg;
					$msg = "Quantity in $binMsg of item: '".$iKey."' has been consumed. Can't change the Item '".$iKey."' in Line#". ($LineNo+1);
					$errorCode = 'INV-1100';
					$placeholder = ['BIN_MSG' => $binMsg, 'I_KEY' => $iKey, 'LINE_NO' => ($LineNo+1)];
				}

                /** @noinspection PhpUndefinedVariableInspection */
                $gErr->addIAError(
                    $errorCode, __FILE__ . ':' . __LINE__,
                    "Changing item from '" . $iKey . "' to '" . $newItem . "' is not allowed", ['I_KEY' => $iKey, 'NEW_ITEM' => $newItem],
                    $msg, $placeholder
                );
				$ok = false;
			}
		}

		return $ok;
	}


    /**
     * @param string $serialNo
     * @param array $maskDetails
     *
     * @return bool
     */
    function ValidateSerialMask($serialNo, $maskDetails){
        $gErr = Globals::$g->gErr;
        $ok = true;

        $itemmask           = $maskDetails['MASK'];
        $itemmaskNoQuotes   = str_replace("'", "", $itemmask);    // remove the single quotes
        $pattern            = $maskDetails['REG_EX_PATTERN'];

        if(isset($pattern) && $pattern!='') {
            if (!preg_match($pattern, $serialNo) || (strlen($itemmaskNoQuotes) != strlen($serialNo))) {
                $ok = false;
            }
        }

		if (!$ok) {
			$msg = "Serial number $serialNo is not as per masking $itemmask";
			$gErr->addIAError(
			    'INV-1041', __FILE__ . ':' . __LINE__,
			    $msg, ['SERIAL_NO' => $serialNo, 'ITEMMASK' => $itemmask]
			);
		}

        return $ok;
    }

    /**
     * @access    private
     *
     * @param array        $track
     * @param bool         $trackingInfoEnabled_forItem
     * @param array        $itementry
     * @param array|string $item
     * @param array        $entry
     * @param array        $itemsHavingChildren
     * @param int|string|float   $lineqty
     * @param bool         $isBuildKitTxn
     * @param bool         $isDisassembleKitTxn
     *
     * @return array
     */
    function PrepTrackingItemDetails($track, $trackingInfoEnabled_forItem, $itementry, $item, &$entry,
                                     &$itemsHavingChildren, &$lineqty, $isBuildKitTxn, $isDisassembleKitTxn)
    {
		$gManagerFactory = Globals::$g->gManagerFactory;
		$itemMgr	= $gManagerFactory->getManager('item');
		$trackParams = $this->_trackParams;
		$itemdetails1 = array();
		$itemdetails = $itementry;

		$itemdetails['PRECISION']				= $itemMgr->_lookUpItemPrecision($item, $trackParams['MOD']);
		$itemdetails['L_NO']					= $entry['LINENO'];
		$itemdetails['LINENO']					= $entry['LINENO'];
		$itemdetails['OLDQTY']					= $entry['OLDQTY'];
		$itemdetails['SERIALTRACKING']			= $item['ENABLESNO'];
		$itemdetails['LOTTRACKING']				= $item['ENABLELOT'];
		$itemdetails['BINTRACKING']				= $item['ENABLEBIN'];
		$itemdetails['EXPTRACKING']				= $item['ENABLEEXPIRATION'];
		$itemdetails['SOURCE_DOCLINEKEY']		= $entry['SOURCE_DOCLINEKEY'];
		$itemdetails['ADJDOCENTRYKEY']			= $entry['ADJDOCENTRYKEY'];
		$itemdetails['COMPONENTDIMKEY']		    = $itementry['COMPONENTDIMKEY'];
		if(isset($track[0]) && $trackParams['INV_TRACK_PREF_ENABLED'] && $trackingInfoEnabled_forItem){
			$lineqty=0;
			$i = 0;
            foreach ( $track as &$tval ) {
                if ( $isBuildKitTxn && StkitDocumentManager::isStockableKitComponentTrackingEnabled()
                     && isset($tval['COMPONENTID']) ) {
                    // Yes, tracked components being consumed; must be accounted for
                    if ( ! empty($tval['COMPONENTID'])
                         && explode('--', $tval['ITEMID'] ?? '')[0] == $itementry['ITEMID']
                         && $this->isItemEnabledForTracking($tval['COMPONENTID']) ) {
                        // This is a real component that's enabled for tracking, corresponding to current component
                        $itemId = $tval['COMPONENTID'];
                    } else {
                        // No actual component specified, different component, or not enabled for tracking; ignore
                        continue;
                    }
                } else if ( $isBuildKitTxn && StkitDocumentManager::isStockableKitTrackingEnabled()
                            && ! isset($tval['COMPONENTID']) ) {
                    // No, tracked stockable kits being produced; costing not relevant; ignore tracking specification
                    continue;
                } else if ( $isDisassembleKitTxn && StkitDocumentManager::isStockableKitComponentTrackingEnabled() ) {
                    // Just in case tracking itemid specified in extended format
                    $tvalItemId = explode('--', $tval['ITEMID'] ?? '')[0];
                    if ( $tvalItemId != $itemdetails['ITEMID'] ) {
                        // Doesn't pertain to this itemdetail, move on
                        continue;
                    } else {
                        $itemId = $tvalItemId;
                    }
                } else {
                    $itemId = $tval['ITEMID'];
                }
                $itemdetails['ITEMID'] = $itemId;
				$itemdetails['QUANTITY']		=$tval['QUANTITY'];
				$itemdetails['SERIALNO']		=$tval['SERIALNO'];
				$itemdetails['LOTNO']			=$tval['LOTNO'];
				$itemdetails['AISLEKEY']		=$tval['AISLEKEY'];
				$itemdetails['ROWKEY']			=$tval['ROWKEY'];
				$itemdetails['BINKEY']			=$tval['BINKEY'];
				$itemdetails['EXPIRATIONDATE']	=$tval['EXPIRATION'];

				$itemdetails1[$i]				=$itemdetails;

                $lineqty = ibcadd($lineqty, $tval['QUANTITY'], $itemdetails['PRECISION'], false);
				$i=$i+1;

				// Ref: EDIT_MODE_ITEM_CHANGE_VALIDATION
				// removing the child references if it exists in the edited document
				// this is for the checking the change in item from the original entry
				if( $this->_action == EDIT_ACTION && $tval['SERIALNO']!='' ){
					unset($itemsHavingChildren[$tval['ITEMID']][$tval['SERIALNO']]);
				}
				if( $this->_action == EDIT_ACTION && $tval['LOTNO']!='' ){
					unset($itemsHavingChildren[$tval['ITEMID']][$tval['LOTNO']]);
				}
                /** @noinspection PhpUndefinedVariableInspection */
                if( $itemEnabledfor == BINNO_ENABLED){
					$aislerowbinkey = $tval['ITEMLINENO']."|".$tval['AISLEID']."|".$tval['ROWID']."|".$tval['BINID']."|".$tval['EXPIRATION'];
					unset($itemsHavingChildren[$tval['ITEMID']][$aislerowbinkey]);
				}
			}
		} else {
			$itemdetails1[0]=$itemdetails;
            $lineqty = ibcadd($lineqty, $itementry['QUANTITY'], $itemdetails['PRECISION'], false);
		}

		return $itemdetails1;
	}


	// validating the business/workflow use cases

    /**
     * @param array $values
     * @param array $entry
     * @param array $trackingInfo
     *
     * @return bool
     */
    private function ValidateTrackingInfo(&$values, $entry, &$trackingInfo)
    {
        $ok = true;
        $itemID = $trackingInfo[0]['ITEMID'];

        $trackingInfoEnabled_forItem = $this->isItemEnabledForTracking($itemID);

        // Back orders should not modify the tracking info when editing
        if ($trackingInfoEnabled_forItem
            && $this->_trackParams['ISBACKORDER']
            && $this->_trackParams['AFFECTS_ONHAND_QTY']
            && $this->_action == EDIT_ACTION) {
            if (!$this->validateBackOrder($values, $entry, $trackingInfo)) {
                return false;
            }
        }

        $serialEnabled = $this->isItemEnabledForTracking($itemID, SERIALNO_ENABLED);
        $lotEnabled = $this->isItemEnabledForTracking($itemID, LOTNO_ENABLED);
        $binEnabled = $this->isItemEnabledForTracking($itemID, BINNO_ENABLED);

        if ($serialEnabled) {
            $ok = $ok && $this->ValidateSerialTracking($values, $entry, $trackingInfo);
        }

        if ($lotEnabled) {
            // note: does not validate lot tracking for sales!
            // I suppose those are caught in the costing layer?
            $ok = $ok && $this->ValidateLotTracking($values, $entry, $trackingInfo);
        }

        if ($binEnabled && !$serialEnabled && !$lotEnabled) {
            $ok = $ok && $this->ValidateBinTracking($values, $entry, $trackingInfo);
        }
        return $ok;
    }


    /**
     *  How do you match two tracking records?  Or a tracking record with some availability?
     *  this routine returns a 'unique key', a string like:
     *
     *  itemID -- Warehouse -- SN -- Lot -- Bin -- Expiration
     *
     * @param string[]      $trackingRecord     One tracking record from TRACKINGENTRIES, or the equivelent
     * @param string        $warehouseID        Tracking records have no warehouse, so use this, otherwise
     *                                          assume the warehouse is in $trackingRecord['WAREHOUSEID']
     *
     * @return string                           a 'unique' key with the concatenation of fields.
     *
     */
    private function trackingKey($trackingRecord, $warehouseID = null)
    {
        if ($warehouseID === null) {
            $warehouseID =   $trackingRecord['WAREHOUSEID'] ?? '';
        }

        [ $warehouseID ] = explode('--', $warehouseID ?? '');
        [ $itemID      ] = explode('--', $trackingRecord['ITEMID'] ?? '');


        return $itemID                            . '--'
            .  $warehouseID                       . '--'
            . ($trackingRecord['BINKEY']   ?? '') . '--'
            . ($trackingRecord['SERIALNO'] ?? '') . '--'
            . ($trackingRecord['LOTNO']    ?? '') . '--'
            . ($trackingRecord['EXPIRATIONDATE'] ?? ($trackingRecord['EXPIRATION'] ?? ''));
    }


    /**
     *  Odd name, I agree.  Elsewhere in this module we see if, for example, there are enough of LOT7.
     * And then, separately, we see if there is enough of BIN12.  But we don't see if there is enough
     * of LOT7 IN BIN12.  Here we do that.
     *
     *  This used to be caught by the costing code when it couldn't resolve what you wanted.  BUT,
     * we now want to support RESERVE and ALLOCATE, which is much harder to do down in the costing code....
     *
     *  We assume here, from how we're called, that this transaction affects ONHAND and will create
     * DocEntryCost records.  So, NOT a Sales Order, but a Shipper or Invoice, say.  Therefore, this transaction
     * itself will not have RESERVE or ALLOCATE values within it.
     *
     * @param array $values
     *
     * @return bool
     */
    public function validateReserveAllocteTracking($values)
    {
        $trackParams = $this->_trackParams;
        $ok          = true;

        $addError = function($err, $entry, $trackingEntryNumber, $placeholder) {
            $where = sprintf("on line %1s, tracking entry %2s", $entry['LINE_NO'] + 1, $trackingEntryNumber);
            Globals::$g->gErr->addIAError(
                'INV-1070', __FILE__ . ':' . __LINE__,
                $err, $placeholder,
                $where, ['ENTRY_LINE_NO' => $entry['LINE_NO'] + 1, 'TRACKING_ENTRY_NUMBER' => $trackingEntryNumber]
            );//I18N::TODO (code change review)
        };

        // this was checked by the caller, but lets be paranoid:
        $isBuildKitTxn = ($values['DOCPARID']==StkitDocumentManager::BUILDKIT) ? true : false;
        $isDisassembleKitTxn = ($values['DOCPARID']==StkitDocumentManager::DISKIT) ? true : false;
        if ( ! $trackParams['AFFECTS_ONHAND'] || ! ($trackParams['ISSALES'] || $isBuildKitTxn) ||
             ! InventoryWQOrderManager::featureEnabled(InventoryWQOrderManager::FEATURE_FLAG_ONLY)) {
            throw new Exception("[Code bug] validateReserveAllocteTracking called under wrong assumptions");
        }

        // Get the tracking data into the document.
        // This annotates the ENTRIES lines; if they are NOT annotated, ignore
        // the ENTRY because it doesn't get tracked or does not have allocated/reserved
        // entries against it.
        $ok = $ok && $this->fetchAvailableTracking($values);
        if ($ok && ($values['SKIP_TRACKING_CHECK'] !== true) ) { // no allocate/reserve???

            $available = $values['AVAILABLE_TRACKING'];

            foreach ($values['ENTRIES'] as $entry) {
                if (isset($entry['TRACKINGENTRIES'])) {
                    $warehouseID = $entry['WAREHOUSE']['LOCATION_NO'] ?? '';
                    foreach ($entry['TRACKINGENTRIES'] as $oneTrackEntry => $oneTrack) {

                        //Build txns need to skip certain tracking entries
                        if ($isDisassembleKitTxn && isset($oneTrack['COMPONENTID']) && $oneTrack['COMPONENTID'] != '') {
                            continue; //If we are disassemblying then we don't need to check qty availability on the components
                        } else if ($isBuildKitTxn && !isset($oneTrack['COMPONENTID'])) {
                            continue; //If we are building a stockable kit then we don't need to check qty qvailability on the SK
                        }

                        $key                = $this->trackingKey($oneTrack, $warehouseID);
                        $desiredQuantity    = $oneTrack['QUANTITY'] ?? 0;
                        $availableQuantity  = $available[$key]['QTYLEFT'] ?? 0;
                        if ($desiredQuantity > $availableQuantity) {
                            $addError( sprintf("There is not enough inventory available for item %1s at warehouse %2s",
                                $oneTrack['ITEMID'], $warehouseID ),
                                $entry, $oneTrackEntry + 1, ['ONE_TRACK_ITEMID' => $oneTrack['ITEMID'], 'WAREHOUSEID' => $warehouseID] );
                                //I18N::TODO (code change review)
                            $ok = false;
                            break;
                        }

                        // decrement it in case another item wants some too!
                        $available[$key]['QTYLEFT'] = ibcsub($availableQuantity, $desiredQuantity, ItemManager::AVERAGE_COST_DECIMALS,true);
                    }
                }
            }
        }
        return $ok;
    }


    /**
     *      If you want tracking information for a number of items, this is where you want to be....
     *  You pass in a document tree, and you'll get back tracking data for each ENTRIES row.
     *  Existing entries are 'added-back-in' to the list so you don't complain about stuff being missing when
     *  it has already been vetted.  That way, you won't 'double count' those entries.
     *  If the item is a KIT or STOCKABLE KIT, tracking for the COMPONENTS will be returned, not the item itself.
     *
     * More about the existing records.  Say you are looking for available tracking for your document.
     * We will 'add back' any quantities alredy consumed by that line.
     * For example, say the line had a serial number on it, but you've saved the document and when you ask for serial
     * numbers, THAT serial number will not come back as available.  How do you know, then, that the SN is wrong?
     * Conversely, if that line is new, you don't want to ignore the SN.
     *
     * Any item that is not an Inventory item, like Kits, Stockable Kits, Non-Inventory, WILL NOT BE RETURNED.
     * Any item that has no tracking possible, WILL NOT BE RETURNED.
     * Any item that HAS tracking, but none is available, WILL NOT BE RETURNED.
     *
     * Finally, if this item does not affect quantity on hand or there is no tracking, we don't account for
     * any RESERVED or ALLOCATED values here....  You're on your own for that....
     *
     *
     * @param array     $documentTree               The Document Manager to check; it is updated with the tracking
     *                                              data available in [ENTRIES][i][AVAILABLE][]
     *
     * @return bool                                 Did the sql queries work?
     *
     */
    public function fetchAvailableTracking( & $documentTree)
    {
        $documentTree['SKIP_TRACKING_CHECK'] = true;
        if (empty($documentTree['ENTRIES'])) {
            return true;
        }

        // ******************************************************************************
        // ******************************************************************************
        //
        // Internal functions
        //
        // ******************************************************************************
        // ******************************************************************************


        /**
         *  Make a list of items and warehouses
         *
         * @param array         $documentTree   document tree from DocumentManager
         * @param array         $itemIDs        Out: item array with the itemid as the KEY
         *                                          and WAREHOUSEIDs in the value (an array)
         * @param string[]      $warehouseIDs   Out: warehouse array with the warehouseid as the KEY
         *
         * @return bool
         */
        $listOfItemsAndWarehouses = function($documentTree, &$itemIDs, &$warehouseIDs) {
            $itemIDs                = [];
            $warehouseIDs           = [];
            $isDisassembleKitTxn    = ($documentTree['DOCPARID']==StkitDocumentManager::DISKIT) ? true : false;

            foreach ($documentTree['ENTRIES'] as $entryIndex => $entry) {

                // gotta have a warehouse
                if (! isset($entry['WAREHOUSE']['LOCATION_NO'])) {
                    continue;
                }
                list($warehouseID) = explode("--", $entry['WAREHOUSE']['LOCATION_NO']);

                // Here, are
                // - one item for normal transactions
                // - list of kit components
                // - list of stockable kit components
                foreach ($entry['ITEMDETAILS'] as $detailsIndex => $row) {

                    //For disassembling, we need the SK id, otherwise, we need the item id itself
                    $rowItemPath = ($isDisassembleKitTxn)? 'PARENTID' : 'ITEMID';

                    // there has to be an item id on this row,
                    // and it has to be enabled for tracking,
                    // or we don't care about it
                    list($itemID) = explode("--", $row[$rowItemPath] ?? '');
                    if (($itemID == '') ||
                        (! $this->isItemEnabledForTracking($itemID))) {
                        continue;
                    }
                    $item     = $this->_itemsRawCache[$itemID];
                    $itemType = $item['ITEMTYPE'] ?? 'I';

                    $mulQty   = (($entry['ITEMTYPE'] === 'SK') && ($itemType !== 'SK'));
                    $mulQty   = $mulQty || (($entry['ITEMTYPE'] === 'K') && ($itemType !== 'K'));
                    if ($mulQty) {
                        $documentTree['ENTRIES'][$entryIndex]['ITEMDETAILS'][$detailsIndex]['FULL_QUANTITY'] =
                             ibcmul($entry['QUANTITY'],$row['QUANTITY'], ItemManager::AVERAGE_COST_DECIMALS, true);
                    }

                    // collect the data for later.....
                    if (!isset($itemIDs[$itemID])) {
                        $itemIDs[$itemID] = ['WAREHOUSEID' => []];
                    }
                    $itemIDs[$itemID]['WAREHOUSEID'][] = $warehouseID;   // may be more than one warehouse for an item
                    $itemIds[$itemID]['ITEMTYPE']      = $itemType;
                    $warehouseIDs[$warehouseID]        = true; // eliminate dups

                    //If disassembling, we can just iterate once for the entry item itself and no need to collect the components
                    if ($isDisassembleKitTxn) {
                        break;
                    }
                }
            }
            return true;
        };


        /**
         *      Get reserved and allocated.  If there IS none, then maybe we don't need to do any more work!
         *
         * @param array     $itemIDs            array of items of interest
         * @param string[]  $warehouseIDs       array of warehouses of interest
         *
         * @return array                        table of results, may be empty!
         */
        $getReservedAllocated = function($itemIDs, $warehouseIDs) {
            // if warehouse fulfillment is enabled, we want to SUBTRACT OUT the allocated items
            // (allocated Quantity is NEGATIVE)
            $allocated = [];
            if (InventoryWQOrderManager::featureEnabled(InventoryWQOrderManager::FEATURE_FLAG_ONLY)) {
                $qry     = [];
                $qry[0] .= "SELECT itemid, warehouseid, binkey, 
                                serialno, lotno, expirationdate, allocatedQuantity as qtyLeft
                                FROM    V_INVTRACKINGALLOCATED
                                WHERE   cny# = :1 ";
                $qry[]  = GetMyCompany();   // well, this is our first parameter
                // add the items
                $qry    = PrepINClauseStmt( $qry, array_keys($itemIDs), ' and itemid ' );
                // and the warehouses
                $qry    = PrepINClauseStmt( $qry, array_keys($warehouseIDs), ' and warehouseid ' );
                $rtn    = QueryResult($qry);
                if ($rtn === false) {
                    $rtn = [];
                }
                // we may get too many rows; trim them
                // (We want a specific warehouse (or two) for a specific item)
                foreach ($rtn as $row) {
                    $itemID             = $row['ITEMID'];
                    $warehouseID        = $row['WAREHOUSEID'];
                    $relevantWarehouses = $itemIDs[$itemID]['WAREHOUSEID'];
                    if (in_array($warehouseID, $relevantWarehouses, true)) {
                        $key             = $this->trackingKey($row);
                        $allocated[$key] = $row;
                    }
                }
            }
            return $allocated;
        };


        /**
         *  Build and run the sql query to fetch availability...
         *
         *  We look up the items' tracking availability, including accounting for reserve and allocate,
         *      less the docentry records specified
         *
         * @param array         $itemIDs                Item array with the itemid as the KEY
         *                                                  and WAREHOUSEIDs in the value (an array)
         * @param string[]      $warehouseIDs           Warehouse array with the warehouseid as the KEY
         *
         * @return array|bool                           The indexed result of the query, or false
         */
        $doSqlQuery = function($itemIDs, $warehouseIDs) {
            // we get items and warehouses we care about.
            // we'll get too much data because we can't say 'item X from warehouse Y', so we'll filter the results
            $qry    = [];
            $qry[0] = "";
            // add all the IN clauses now, so we can save them for later...
            $qry[1] = GetMyCompany();   // well, this is our first parameter
            // add the items
            $qry    = PrepINClauseStmt( $qry, array_keys($itemIDs), ' and itemkey ' );
            // and the warehouses
            $qry    = PrepINClauseStmt( $qry, array_keys($warehouseIDs), ' and whsekey ' );
            $inClauses = $qry[0];

            // now we have the IN clauses, lets add them where needed, but we don't need to
            // keep generating more and more of them....
            $qry[0] = "SELECT itemkey as itemid, WHSEKEY as warehouseid, binkey, serialno, lotno, expirationdate, sum(totalQty) qtyleft
                     FROM (SELECT itemkey, WHSEKEY, binkey, serialno, lotno, expirationdate, sum(qtyleft) totalQty
                                FROM  docentrycost
                                WHERE cny#=:1 AND qtyleft > 0
                                  AND in_out = 'I' AND affects_inventory in ('V', 'QV') and adjdocentrycostkey IS NULL 
                                  $inClauses
                                GROUP BY itemkey, WHSEKEY, binkey, serialno, lotno, expirationdate
                                UNION
                                SELECT itemkey, WHSEKEY, binkey, serialno, lotno, expirationdate, sum(qtyleft) totalQty
                                FROM docentrycostkits 
                                WHERE cny#=:1 AND qtyleft > 0
                                  AND in_out = 'I' AND affects_inventory in ('V', 'QV')
                                  $inClauses
                                GROUP BY itemkey, WHSEKEY, binkey, serialno, lotno, expirationdate
                        )
                   GROUP BY itemkey, WHSEKEY, binkey, serialno, lotno, expirationdate ";

            // Cross your fingers.....
            $rawResult = QueryResult($qry);
            if ($rawResult === false) {
                return false;
            }

            // make an index
            $result    = [];
            foreach ($rawResult as $row) {
                $key          = $this->trackingKey($row);
                $result[$key] = $row;
            }
            return $result;
        };


        /**
         *  After we do the query, we may have some entries that
         *      - have no availability
         *      - are for an item/warehouse combination the caller did not ask for
         *
         * @param array     $result         In and Out: the query result
         * @param array     $allocated      what has been allocated and reserved?
         *
         */
        $blendResultsOfQueryAndAllocated = function(&$result, $allocated) {

            // add in the allocate/reserve numbers.  Remember they are NEGATIVE
            foreach ($allocated as $key => $avail) {
                if (isset($result[$key])) {
                    $result[$key]['QTYLEFT'] =
                        ibcadd($result[$key]['QTYLEFT'], $avail['QTYLEFT'], ItemManager::AVERAGE_COST_DECIMALS, true);
                } else {
                    // add it to the results
                    $result[$key] = $avail;  // same format!
                }
            }

            // did some go negative?
            // warehouses we don't care about?
            foreach ($result as $key => $row) {
                if ($row['QTYLEFT'] <= 0) {
                    unset($result[$key]);
                }
            }
        };


        /**
         *  The query results might include some binkeys (not IDs), and the client may want
         *      Bin IDs.  So fetch them now.
         *
         * @param array     $result         Query result, perhaps with some bin keys
         */
        $getBinIDsFromBinKeys = function(&$result) {
            // got bins?  Get the ID for the keys
            $binKeys = [];
            foreach ($result as $row) {
                if (isset($row['BINKEY']) && $row['BINKEY'] != 0) {
                    $binKeys[$row['BINKEY']] = true;
                }
            }
            if ( ! empty($binKeys)) {
                $binKeys = BinManager::BinIdsForKeys(array_keys($binKeys));
                foreach ($result as $index => $row) {
                    if (isset($row['BINKEY']) && $row['BINKEY'] != 0) {
                        $result[$index]['BINID'] = $binKeys[$row['BINKEY']] ?? '?'; // We don't expect a failure, but....
                    }
                }
            }
        };



        /**
         *  We have the list of available tracking.  BUT, if the current document had been saved
         *  previously with tracking, we want to add that back into the available tracking.
         *
         * @param array     $documentTree   The DocumentManager record
         * @param array     $result         Query result to be updated
         *
         * @return bool
         */
        $addBackInExistingEntriesForCurrentDocument = function($documentTree, & $result) {

            $addOneTrackingEntryBack = function($trackRecord, $warehouseID, & $result) {
                $key = $this->trackingKey($trackRecord, $warehouseID);
                if (isset($result[$key])) {
                    $result[$key]['QTYLEFT'] =
                        ibcadd($result[$key]['QTYLEFT'], $trackRecord['QUANTITY'], ItemManager::AVERAGE_COST_DECIMALS, true);
                } else {
                    $trackRecord['QTYLEFT']           = $trackRecord['QUANTITY']; // these start out the same
                    $trackRecord['WAREHOUSEID']       = $warehouseID;
                    $trackRecord['EXPIRATIONDATE']    = $trackRecord['EXPIRATION'];
                    $result[$key]                     = $trackRecord;  // now the same format!
                }
            };

            // we don't worry about which entry these came from; they were all saved, and therefore
            // we assume they were valid before.
            //
            //  Also, add in the relevant warehouse, which is not a part of the tracking record.
            //
            // If this is an update, we can use EXISTING_ENTRIES, otherwise use ENTRIES
            // and look for a RECORDNO (from a convert)
            if (isset($documentTree['EXISTING_ENTRIES'])) {
                foreach ($documentTree['EXISTING_ENTRIES'] as $entry) {
                    if (isset($entry['EXISTING_TRACKINGENTRIES'])) {
                        $warehouseID = $entry['WAREHOUSE']['LOCATION_NO'] ?? '';
                        foreach ($entry['EXISTING_TRACKINGENTRIES'] as $trackRecord) {
                            $addOneTrackingEntryBack($trackRecord, $warehouseID, $result);
                        }
                    }
                }
            } else {
                foreach ($documentTree['ENTRIES'] as $entry) {
                    if (isset($entry['TRACKINGENTRIES'])) {
                        $warehouseID = $entry['WAREHOUSE']['LOCATION_NO'] ?? '';
                        foreach ($entry['TRACKINGENTRIES'] as $trackRecord) {
                            // bulk convert preserves the old RECORDNO, DocumentFormEditor does not, but I
                            // saved the old record number as PRIOR_RECORDNO :-)
                            // (since we are adding, the old record number will be ignored)
                            $recordNumber = $trackRecord['RECORDNO'] ?? ($trackRecord['PRIOR_RECORDNO'] ?? 0);
                            if ($recordNumber > 0) {    // this is an add, but a convert too
                                $addOneTrackingEntryBack($trackRecord, $warehouseID, $result);
                            }
                        }
                    }
                }
            }
            return true;
        };


        // ******************************************************************************
        // ******************************************************************************
        //
        // Main code (uses the functions above)
        //
        // ******************************************************************************
        // ******************************************************************************

        // 0) caller should have done this, but if they have not yet....
        if (empty($this->_trackParams)) {
            $this->PrepTrackingParams($documentTree);
        }

        // First, Make a list of items and warehouses
        $itemIDs      = [];
        $warehouseIDs = [];
        $listOfItemsAndWarehouses($documentTree, $itemIDs, $warehouseIDs);
        // anything there?
        if (empty($itemIDs)) {
            return true;
        }

        // are any of the item/warehouse combos allocated or reserved?
        $allocated = $getReservedAllocated($itemIDs, $warehouseIDs);
        // if no return, then nothing we care about was reserved or allocated
        //
        if (empty($allocated)) {
            return true;    // so the 'normal' tracking routines will work
        }

        // from this point on, if we return something pay attention to it!
        $documentTree['SKIP_TRACKING_CHECK'] = false;

        // Next, get the sql to look up the items' tracking availability,
        $result = $doSqlQuery($itemIDs, $warehouseIDs);
        if ($result === false) {
            return false;
        }

        // might be empty, might be too many; filter here:
        $blendResultsOfQueryAndAllocated($result, $allocated);

        // Next, add in any existing saved tracking for the current document
        $addBackInExistingEntriesForCurrentDocument($documentTree, $result);

        // got bins?  Get the ID for the keys
        $getBinIDsFromBinKeys($result);

        // Finally, update the document tree to contain the available tracking.
        $documentTree['AVAILABLE_TRACKING'] = $result;

        return true;
    }


    /**
     * @param array $values
     * @param array $entry
     * @param array $trackingInfo
     *
     * @return bool
     */
    private function validateBackOrder($values, $entry, $trackingInfo)
    {
        $gErr = &Globals::$g->gErr;

        $lineNo = $entry['LINE_NO'] + 1;
        $itemId = $entry['ITEMID'];

        //
        // get the existing tracking info
        $docEntryKey = $entry['RECORDNO'];
        $existingEntry = $values['EXISTING_ENTRIES'][$docEntryKey];

        $whseKey = $entry['WAREHOUSE']['LOCATION_NO'];
        $existingWhseKey = $existingEntry['WAREHOUSE']['LOCATION_NO'];

        //
        // if warehouse has changed, then throw error
        if ($whseKey != $existingWhseKey) {
            $gErr->addIAError(
                'INV-1042', __FILE__ . ':' . __LINE__,
                "Changing tracking info in back order is not allowed", [],
                null, ['ITEM_ID' => $itemId, 'LINE_NO' => $lineNo]
            );
            return false;
        }

        //
        // if the entry doesn't exist in the existing values thenit is newly added
        if (!$existingEntry) {
            $gErr->addIAError(
                'INV-1043', __FILE__ . ':' . __LINE__,
                "Changing tracking info in back order is not allowed", [],
                null, ['ITEM_ID' => $itemId, 'LINE_NO' => $lineNo]
            );
            return false;
        }

        //
        // if there is any change in the Quantity throw error
        $existingQty = $existingEntry['QUANTITY'];
        $currentQty = $entry['QUANTITY'];
        if ($existingQty != $currentQty) {
            $gErr->addIAError(
                'INV-1044', __FILE__ . ':' . __LINE__,
                "Changing tracking info in back order is not allowed", [],
                null, ['ITEM_ID' => $itemId, 'LINE_NO' => $lineNo]
            );
            return false;
        }

        //
        // prepare keys for existing tracking entries
        $existingTrackingEntries = array();
        foreach ($existingEntry['EXISTING_TRACKINGENTRIES'] as $tInfo) {
            $tInfoKey = $tInfo['TRACK_QUANTITY'] . '|';
            $tInfoKey .= $tInfo['SERIALNO'] . '|';
            $tInfoKey .= $tInfo['LOTNO'] . '|';
            $tInfoKey .= $tInfo['AISLEKEY'] . "|";
            $tInfoKey .= $tInfo['ROWKEY'] . "|";
            $tInfoKey .= $tInfo['BINKEY'] . "|";
            $tInfoKey .= $tInfo['EXPIRATION'];

            $existingTrackingEntries[] = $tInfoKey;
        }

        //
        // prepare keys for current tracking entries
        $currentTrackingEntries = array();
        foreach ($trackingInfo as $tInfo) {
            $tInfoKey = $tInfo['TRACK_QUANTITY'] . '|';
            $tInfoKey .= $tInfo['SERIALNO'] . '|';
            $tInfoKey .= $tInfo['LOTNO'] . '|';
            $tInfoKey .= $tInfo['AISLEKEY'] . "|";
            $tInfoKey .= $tInfo['ROWKEY'] . "|";
            $tInfoKey .= $tInfo['BINKEY'] . "|";
            $tInfoKey .= $tInfo['EXPIRATION'];

            $currentTrackingEntries[] = $tInfoKey;
        }

        //
        // if count of tracking entries doesn't match
        if (count($existingTrackingEntries) != count($currentTrackingEntries)) {
            $gErr->addIAError(
                'INV-1045', __FILE__ . ':' . __LINE__,
                "Changing tracking info in back order is not allowed", [],
                null, ['ITEM_ID' => $itemId, 'LINE_NO' => $lineNo]
            );
            return false;
        }

        //
        // if the tracking info is modified
        $isTrackingInfoModified = array_diff($existingTrackingEntries, $currentTrackingEntries) ? true : false;
        if ($isTrackingInfoModified) {
            $gErr->addIAError(
                'INV-1046', __FILE__ . ':' . __LINE__,
                "Changing tracking info in back order is not allowed", [],
                null, ['ITEM_ID' => $itemId, 'LINE_NO' => $lineNo]
            );
            return false;
        }

        return true;
    }

    /**
     * @param array $docpar
     *
     * @return bool
     */
    function AffectsOnHAndQuantity($docpar){
        $gManagerFactory = Globals::$g->gManagerFactory;
		$affects_OnHandQty = false;

		if(!isset($docpar['DOCPAR_TOTALS'])){
			$docpartotalsManager	 = $gManagerFactory->getManager('documentpartotals');
			$docpar['DOCPAR_TOTALS'] = $docpartotalsManager->getByParent($docpar['RECORDNO']);
		}
		//if in TD , totals are affeacting ONHAND qty then
        foreach( $docpar['DOCPAR_TOTALS'] as $total){
			if($total['TOTALID']=='ONHAND' && ($total['Q_QV']=='Quantity' || $total['Q_QV']=='Quantity & Value')){
				$affects_OnHandQty =true;
			}
		}
		return $affects_OnHandQty;
	}

    /**
     * @param array $docpar
     *
     * @return bool
     */
    function AffectsOnHAndValueOnly($docpar){
        $gManagerFactory = Globals::$g->gManagerFactory;
        $affects_OnHandValueOnly = false;

        if(!isset($docpar['DOCPAR_TOTALS'])){
            $docpartotalsManager	 = $gManagerFactory->getManager('documentpartotals');
            $docpar['DOCPAR_TOTALS'] = $docpartotalsManager->getByParent($docpar['RECORDNO']);
        }
        //if in TD , totals are affeacting ONHAND qty then
        foreach( $docpar['DOCPAR_TOTALS'] as $total){
            if($total['TOTALID']=='ONHAND' && ($total['Q_QV']=='Value')){
                $affects_OnHandValueOnly =true;
            }
        }
        return $affects_OnHandValueOnly;
    }


    /**
     * @param array $docpar
     *
     * @return null|int
     */
    function GetOnHAndTotal($docpar){
        $gManagerFactory = Globals::$g->gManagerFactory;

        if(!isset($docpar['DOCPAR_TOTALS'])){
            $docpartotalsManager	 = $gManagerFactory->getManager('documentpartotals');
            $docpar['DOCPAR_TOTALS'] = $docpartotalsManager->getByParent($docpar['RECORDNO']);
        }
        //if in TD , totals are affeacting ONHAND then
        foreach( $docpar['DOCPAR_TOTALS'] as $total){
            if($total['TOTALID']=='ONHAND'){
                return $total['Q_QV'];
            }
        }
        return null;
    }

	// ----------- Serial Tracking validation methods ---------------//
	//function ValidateSerialTracking
    /**
     * @param array $values
     * @param array $entry
     * @param array $trackingInfo
     *
     * @return bool
     */
    function ValidateSerialTracking(&$values, $entry, &$trackingInfo){
		$trackParams = $this->_trackParams;
		$ok = true;
		// validate line items Quantity and track Quantity

		// validate Sales / Purchase return transactions
		if($trackParams['ISSALES'] || $trackParams['ISPURCHASE_RETURN']){
			$ok = $ok && $this->ValidateSerialTracking_Sales_POReturns($values, $entry, $trackingInfo);
		}
		//
		//  validate purchase trnasactions
		if($trackParams['ISPURCHASE']){
			$ok = $ok && $this->ValidateSerialTracking_PurchaseDocs($values, $entry, $trackingInfo);
		}
		//
		// validate Sales Return transactions
		if($trackParams['ISSALES_RETURN']){
			$ok = $ok && $this->ValidateSerialTracking_SalesReturn($values, $entry, $trackingInfo);
		}
		//
		// for all OUT kind of transactions (which decrease ONHAND inventory) Like Shipper, Purchase Return
		// --- ### the condition should also include $trackParams['AFFECTS_ONHAND_QTY']

        if ( $this->isItemEnabledForTracking($entry['ITEMID'], EXPIRATION_ENABLED)
             || ( StkitDocumentManager::isStockableKitComponentTrackingEnabled()
                  && $this->_itemsRawCache[$entry['ITEMID']]['HASTRACKING_ENABLED_COMPONENTS'] ) ) {
            $ok = $ok && $this->ValidateSerialNumberExpiration($values, $trackingInfo, $trackParams['IN_OUT'],$entry);
        }
        
		return $ok;
	}


    /**
     * @param array         $availSerialNumbers     from a query of available serial numbers
     * @param string[]      $serialnumbers          resulting list of serial numbers
     * @param array         $tempserialnumbers      raw data from the query, by SN
     * @param string[]      $consumedSerialNumbers  when no QTYONHAND, this is filled in
     * @param array         $values                 document tree
     * @param array         $entry                  this docentry
     * @param bool          $trackQtyLeft           do we care about QtYLEFT?
     */
	private function getAvailableSerialNumbers($availSerialNumbers, &$serialnumbers, &$tempserialnumbers, &$consumedSerialNumbers, $values, $entry, $trackQtyLeft)
    {
        // Possibly lower the available serial numbers in the list, by
        // removing anything ALLOCATED in Fulfillment
        InventoryWorkQueueDetailsManager::allocatedSerialNumbers($entry['ITEMID'], $availSerialNumbers);

        $serialnumbers          = [];
        $tempserialnumbers      = [];
        $consumedSerialNumbers  = [];
        foreach( $availSerialNumbers as $row){

            if ($trackQtyLeft) {
                if ($row['QTYLEFT'] > 0) {
                    $serialnumbers[] = $row['SERIALNO'];
                    $tempserialnumbers[$row['SERIALNO']] = $row;
                } else {
                    $consumedSerialNumbers[] = $row['SERIALNO'];
                }
            } else {
                $serialnumbers[] = $row['SERIALNO'];
                $tempserialnumbers[$row['SERIALNO']] = $row;
            }
        }

        // Now, if this is an UPDATE of a record, add in the stuff the current record is using.....
        $recno = $entry['RECORDNO'] ?? 0; // 0 means it is a new record
        if (($recno > 0) && isset($values['EXISTING_ENTRIES'][$recno]['EXISTING_TRACKINGENTRIES'])) {
            $existingTracking =   $values['EXISTING_ENTRIES'][$recno]['EXISTING_TRACKINGENTRIES'];
            foreach ($existingTracking as $exTrackingRow) {
                $serialnumbers[] = $exTrackingRow['SERIALNO'];
                $tempserialnumbers[$exTrackingRow['SERIALNO']] = $exTrackingRow;
            }
        }
    }


    /**
     * @param array $values
     * @param array $entry
     * @param array $trackingInfo
     *
     * @return bool
     */
    function ValidateSerialTracking_Sales_POReturns(&$values, $entry, &$trackingInfo){
		$gManagerFactory = Globals::$g->gManagerFactory;
		$gErr = Globals::$g->gErr;

		// $trackingInfo -- is the array
		$trackParams = $this->_trackParams;
		$ok = true;
		$cny		= GetMyCompany();
		$whsekey		= $entry['WAREHOUSE']['LOCATION_NO'];
		$recalledID		= $entry['SOURCE_DOCID'];
		//$docDate		= $values['WHENCREATED'];
		$docentrycostMgr = $gManagerFactory->getManager('documententrycost');

        $parentInfo = [];
        if (isset($entry['SOURCE_DOCKEY']) && $entry['SOURCE_DOCKEY'] != '') {
            $parentInfo = $trackParams['PARENTINFO'][$entry['SOURCE_DOCKEY']];
        }

		if(isset($trackingInfo)){
			$itemid = $trackingInfo[0]['ITEMID'];
		}else{
			$itemid	= $entry['ITEMID'];
		}

		// if purchase return is affecting value only
		// and if it is created directly
		if($recalledID =='' && $trackParams['AFFECTS_ONHAND_VALUE_ONLY']){
			if($trackParams['ISPURCHASE_RETURN']) {
                $ok = $ok && $this->ValidateSerialTracking_POReturns_ValueOnly($values, $entry, $trackingInfo);
            }

            if($trackParams['ISSALES']){
                $ok = $ok && $this->ValidateSerialTracking_Sales_ValueOnly($values, $entry, $trackingInfo);
			}

            return $ok;
		}

		if ($ok && ($trackParams['ISSALES'] || $trackParams['ISPURCHASE_RETURN'])) {
			// when sales is edited / created
			if(($this->_action==EDIT_ACTION || $this->_action==CREATE_ACTION)){
				if($recalledID!=''){
					$qryGetAvailSerialNumbers	= 'QRY_DOCUMENTENTRYCOST_SELECT_AVAIL_PARENT_SERIALNO';

                    if (!empty($parentInfo) && $parentInfo['AFFECTS_ONHAND_QTY']
                        && ($parentInfo['IN_OUT'] != $trackParams['IN_OUT'] || $trackParams['ISBACKORDER'])
                    ) {
						$docMsg = " in '".$recalledID."'";
						$errorCode = 'INV-1085';
						$placeholder = ['RECALLEDID' => $recalledID];
						$argsGetAvailSerialNumbers	= array($itemid, $whsekey, $cny, $recalledID);
					}else{
                        // If the parent is affecting ONHAND quantity
                        // get the serial numbers from parent
                        // else look for available serial numbers in the warehouse
                        $sourceDocIDWithtrackingInfo = $this->getParentWithSerial($entry['SOURCE_DOCLINEKEY']);
                        if ($sourceDocIDWithtrackingInfo != '') {
                            $docMsg = " in '" . $sourceDocIDWithtrackingInfo . " >> " . $recalledID . "'";
                            $errorCode = 'INV-1086';
                            $placeholder = ['SOURCE_DOC_WITHTRACKING_INFO' => $sourceDocIDWithtrackingInfo, 'RECALLEDID' => $recalledID];
                            $argsGetAvailSerialNumbers = array($itemid, $whsekey, $cny, $sourceDocIDWithtrackingInfo);
                        } else {
                            $docMsg = '';
                            $qryGetAvailSerialNumbers = 'QRY_DOCUMENTENTRYCOST_SELECT_AVAIL_SERIALNO';
                            $argsGetAvailSerialNumbers = array($itemid, $whsekey,$cny);
                        }
					}
				}else{
					$docMsg='';
					$qryGetAvailSerialNumbers	= 'QRY_DOCUMENTENTRYCOST_SELECT_AVAIL_SERIALNO';
					$argsGetAvailSerialNumbers	= array($itemid,$whsekey,$cny);
				}
			}

            /** @noinspection PhpUndefinedVariableInspection */
            $availSerialNumbers = $docentrycostMgr->DoQuery($qryGetAvailSerialNumbers, $argsGetAvailSerialNumbers);
            $this->getAvailableSerialNumbers($availSerialNumbers,$serialnumbers,$tempserialnumbers, $consumedSerialNumbers, $values, $entry, false);

            // todo: check docdate with expiration date?

            foreach( $trackingInfo ?? []  as $val)	{
				if(isset($val['SERIALNO'])){
					// if the serial number is not found in the array
					// either it would have been consumed or doesn't exist
                    /** @noinspection PhpUndefinedVariableInspection */
                    if (!in_array($val['SERIALNO'], $serialnumbers)){
						$qry = 'QRY_DOCUMENTENTRYCOST_SELECT_USED_SERIALNO_DOCS_SALE';
						$args = array($itemid,$whsekey,$cny, $val['SERIALNO'] );
						$rows = $docentrycostMgr->DoQuery($qry,$args);

						if((!empty($rows))){
							if($trackParams['AFFECTS_ONHAND_QTY'] && $rows[0]['DOCID']!=$trackParams['DOCID']){
                                $msg = "Serial number '".$val['SERIALNO']."' assigned to Item '".$val['ITEMID']."' in Line# ".($val['ITEMLINENO']+1)." is already consumed by Document  '".$rows[0]['DOCID']."'";
                                $gErr->addIAError(
                                    'INV-1047', __FILE__ . ':' . __LINE__,
                                    $msg, ['VAL_SERIALNO' => $val['SERIALNO'], 'VAL_ITEMID' => $val['ITEMID'], 'VAL_ITEMLINENO' => ($val['ITEMLINENO']+1), 'ROWS_DOCID' => $rows[0]['DOCID']]
                                );
                                $ok=false;
							}
						}
						else{
                            /** @noinspection PhpUndefinedVariableInspection */
                            if( $docMsg != ''){
								$msg = "Serial number '".$val['SERIALNO']."' assigned to Item '".$val['ITEMID']."' in Line# ".($val['ITEMLINENO']+1)." is not available ".$docMsg.".";
								$placeholder = array_merge($placeholder, ['VAL_SERIALNO' => $val['SERIALNO'], 'VAL_ITEMID' => $val['ITEMID'], 'VAL_ITEMLINENO' => ($val['ITEMLINENO']+1)]);
							}else{
								$msg = "Serial number '".$val['SERIALNO']."' assigned to Item '".$val['ITEMID']."' in Line# ".($val['ITEMLINENO']+1)." is not available in warehouse ".$whsekey;
								$errorCode = 'INV-1087';
								$placeholder = ['VAL_SERIALNO' => $val['SERIALNO'], 'VAL_ITEMID' => $val['ITEMID'], 'VAL_ITEMLINENO' => ($val['ITEMLINENO']+1), 'WHSEKEY' => $whsekey];
							}
							$gErr->addIAError($errorCode, __FILE__ . ':' . __LINE__, "Unable to save Document", [], $msg, $placeholder);
							$ok=false;
						}
					}
				}
			}

		}// -------------- sale / purchase return end --------------//

		return $ok;
	}


    /**
     * @param array $values
     * @param array $entry
     * @param array $trackingInfo
     *
     * @return bool
     */
    function ValidateSerialTracking_POReturns_ValueOnly(
        /** @noinspection PhpUnusedParameterInspection */ &$values, $entry, &$trackingInfo)
	{
		$gErr = Globals::$g->gErr;

		// $trackingInfo -- is the array
		$trackParams = $this->_trackParams;
		$ok = true;
		$cny = GetMyCompany();
		$whsekey = $entry['WAREHOUSE']['LOCATION_NO'];
		$recalledID = $entry['SOURCE_DOCID'];

		if($recalledID!='' || !$trackParams['AFFECTS_ONHAND_VALUE_ONLY']){
			return true;
		}

		if (isset($trackingInfo)) {
			$itemid = $trackingInfo[0]['ITEMID'];
		} else {
			$itemid = $entry['ITEMID'];
		}

        // for a po return value only
        // make sure there is a PO return for the same serial number
        // and multiple
        $entrySerialNos = [];
        foreach( $trackingInfo as $val)	{
            $entrySerialNos[] = $val['SERIALNO'];
        }

        if( (!empty($entrySerialNos))) {
            $duplicateReturnQry[0] = "SELECT dh.docid, dec.serialno, dec.affects_inventory FROM docentrycost dec
									INNER JOIN docentrymst de ON de.cny# = dec.cny# AND de.record# = dec.docentrykey
									INNER JOIN dochdrmst dh ON dh.cny# = de.cny# AND dh.record# = de.dochdrkey AND dh.state NOT IN ('I','S','A', 'X', 'R')
									INNER JOIN docparmst dp ON dp.cny# = dh.cny# AND dp.record# = dh.docparkey AND dp.sale_pur_trans = 'P'
									INNER JOIN docpartotals dpt ON dpt.cny# = dp.cny# AND dpt.docparkey = dp.record# AND dpt.SIGN = -1
									INNER JOIN ictotal ict ON ict.cny# = dpt.cny# AND ict.record# = dpt.totalkey AND ict.NAME = 'ONHAND'
									WHERE dec.cny#  = :1
									AND dec.qtyleft > 0
									AND dec.itemkey = :2";

            $duplicateReturnQry[1] = $cny;
            $duplicateReturnQry[2] = $itemid;
            // in edit mode skip checking/validating the current document
            self::addDocumentAndWarehouseFiltersIfNeeded($duplicateReturnQry, $this->_action == EDIT_ACTION, true,
                                                         $trackParams['DOCID'], $whsekey);

            $duplicateReturnQry = PrepINClauseStmt($duplicateReturnQry, $entrySerialNos, " AND dec.serialno ", false, 'dummy', true);
            $invRows = QueryResult($duplicateReturnQry);

            if (Util::countOrZero($invRows) == 0) {
            	$slNos = implode(",", $entrySerialNos);
                /** @noinspection PhpUndefinedVariableInspection */
                $msg = "Could not find any return document with Serial numbers $slNos assigned to Item '" . $itemid . "' in Line# " . ( $lineNo + 1) ;
                $gErr->addIAError(
                    'INV-1048', __FILE__ . ':' . __LINE__,
                    "Return document not found", [],
                    $msg, ['SL_NOS' => $slNos, 'ITEMID' => $itemid, 'LINE_NO' => ($lineNo + 1)]
                );
                return false;
            }else{
				foreach($invRows as $returnDoc){
					if($returnDoc['AFFECTS_INVENTORY'] == 'V' || $returnDoc['AFFECTS_INVENTORY'] == 'QV'){
						$returnDocid = $returnDoc['DOCID'];
                        /** @noinspection PhpUndefinedVariableInspection */
                        $msg = "A return document '$returnDocid' already exists for Serial number '" . $returnDoc['SERIALNO'] . "' assigned to Item '" . $itemid . "' in Line# " . ( $lineNo + 1);
                        $gErr->addIAError(
                            'INV-1049', __FILE__ . ':' . __LINE__,
                            "Return document exists", [],
                            $msg, ['RETURN_DOCID' => $returnDocid, 'RETURN_DOC_SERIALNO' => $returnDoc['SERIALNO'], 'ITEMID' => $itemid, 'LINE_NO' => ($lineNo + 1)]
                        );
                        return false;
					}
				}

			}
        } // ---- ENDS : validating duplicate invoice for same serial numbers

		return $ok;
    }

    /**
     * Determine the itemId from tracking specifications.
     *
     * For most transactions, all the tracking specifications pertain to the item associated
     * with the entry.
     *
     * However, during a build transaction, stockable kit components may also be tracked--and
     * their itemids should be ignored (iow, we do not intend to validate those serial numbers;
     * instead we only wish to check for duplicate serial numbers for the in-process-of-being-built
     * stockable kit). So, we hunt through the tracking specifications until we find one belonging
     * to the stockable kit, otherwise default to the entry's itemid.
     *
     * @param string[]            $entry        Transaction line item
     * @param string[]|string[][] $trackingInfo Tracking specifications
     * @param string[]            $values       Transaction object
     *
     * @return string The desired itemId
     */
    private function getItemIdFromTracking($entry, $trackingInfo, $values)
    {
        $itemId = $entry['ITEMID'];
        foreach ( $trackingInfo as $val ) {
            if ( StkitDocumentManager::isStockableKitComponentTrackingEnabled()
                 && $values['DOCPARID'] == StkitDocumentManager::BUILDKIT
                 && $entry['ITEMTYPE'] == 'SK'
                 && isset($val['COMPONENTID']) ) {
                // Do not check for duplicate serial numbers in stockable kit components
                continue;
            }
            // Found a tracking specification for the entry (stockable kit) itself
            $itemId = $val['ITEMID'];
            break;
        }

        return $itemId;
    }

    /**
     * @param array $values
     * @param array $entry
     * @param array $trackingInfo
     *
     * @return bool
     */
	function ValidateSerialTracking_PurchaseDocs(
        /** @noinspection PhpUnusedParameterInspection */ &$values, $entry, &$trackingInfo)
	{
		$gManagerFactory = Globals::$g->gManagerFactory;
		$gErr = Globals::$g->gErr;

		// $trackingInfo -- is the array
		$trackParams = $this->_trackParams;

        $parentInfo = [];
        if (isset($entry['SOURCE_DOCKEY']) && $entry['SOURCE_DOCKEY'] != '') {
            $parentInfo = $trackParams['PARENTINFO'][$entry['SOURCE_DOCKEY']];
        }

		// if 'value' only document comes with adj key then no need to validate. 
        // It is trying to adjust existing 'Value' layer
		if ($trackParams['AFFECTS_ONHAND_VALUE_ONLY'] && $entry['ADJDOCENTRYKEY']) {
			return true;
		}

		$ok = true;
		$cny = GetMyCompany();
		$whsekey = $entry['WAREHOUSE']['LOCATION_NO'];
		$recalledID	= $entry['SOURCE_DOCID'];
		$lineNo = $entry['LINENO'];
		$docentrycostMgr = $gManagerFactory->getManager('documententrycost', true);

		if(isset($trackingInfo)){
			$itemid = $this->getItemIdFromTracking($entry, $trackingInfo, $values);
		}else{
			$itemid	= $entry['ITEMID'];
		}

        // ---------------- converting -------------//
        if ($recalledID != ''
            && !empty($parentInfo) && $parentInfo['AFFECTS_ONHAND_QTY']
            && $trackParams['AFFECTS_ONHAND_QTY']
        ) {
			$qryGetAvailSerialNumbers	= 'QRY_DOCUMENTENTRYCOST_SELECT_AVAIL_PARENT_SERIALNO_PUR';
			$argsGetAvailSerialNumbers	= array($itemid, $cny, $recalledID);
			$availSerialNumbers = $docentrycostMgr->DoQuery($qryGetAvailSerialNumbers, $argsGetAvailSerialNumbers);
            $this->getAvailableSerialNumbers($availSerialNumbers,$serialnumbers,$tempserialnumbers,$consumedSerialNumbers, $values, $entry, true);

			foreach($trackingInfo as $key=>$val)	{
				if (isset($val['SERIALNO'])) {
                    if (!empty($parentInfo)
                        && ($parentInfo['IN_OUT'] != $trackParams['IN_OUT'] || $trackParams['ISBACKORDER'])) {
						// if the serial number is not found in the array
						// either it would have been consumed or doesn't exist
                        /** @noinspection PhpUndefinedVariableInspection */
                        if (in_array($val['SERIALNO'], ($serialnumbers ?? []))) {
							// refer to the parent if it is
							// sales, sales return, inventory transfer out, purchase return
							if ($trackParams['AFFECTS_ONHAND_QTY'] && empty($trackingInfo[$key]['DOCCOMPONENTKEY'])) {
                                /** @noinspection PhpUndefinedVariableInspection */
                                $trackingInfo[$key]['DOCCOMPONENTKEY'] = $tempserialnumbers[$val['SERIALNO']]['DOCCOMPONENTKEY'] ?? '';
							}
						} /** @noinspection PhpUndefinedVariableInspection */ 
						elseif (in_array($val['SERIALNO'], $consumedSerialNumbers)) {
							$trackingInfo[$key]['QTYLEFT'] = 0;
						} else {
							if($recalledID!=''){
							    $docMsg = "in '".$recalledID."'";
							    $errorCode = 'INV-1072';
							    $placeholder = ['VAL_SERIALNO' => $val['SERIALNO'], 'VAL_ITEMID' => $val['ITEMID'], 'VAL_ITEMLINENO' => ($val['ITEMLINENO']+1), 'RECALLED_ID' => $recalledID];
							}else{
							    $docMsg = ".";
							    $errorCode = 'INV-1050';
							    $placeholder = ['VAL_SERIALNO' => $val['SERIALNO'], 'VAL_ITEMID' => $val['ITEMID'], 'VAL_ITEMLINENO' => ($val['ITEMLINENO']+1)];
							}
							$msg = "Serial number: '".$val['SERIALNO']."' assigned to Item: '".$val['ITEMID']."' in Line# ".($val['ITEMLINENO']+1)." does not exist ".$docMsg;
							$gErr->addIAError(
							    $errorCode, __FILE__ . ':' . __LINE__,
							    $msg, $placeholder
							);
							$ok=false;
						}
					} else {
						$docMsg = $recalledID!='' ? "in '".$recalledID."'" : ".";
						if($recalledID!=''){
						    $docMsg = "in '".$recalledID."'";
						    $errorCodeCase1 = 'INV-1092';
						    $errorCodeCase2 = 'INV-1094';
						    $placeholder = ['RECALLEDID' => $recalledID];
						}else{
						    $docMsg = ".";
						    $errorCodeCase1 = 'INV-1093';
						    $errorCodeCase2 = 'INV-1095';
						    $placeholder = [];
						}
                        /** @noinspection PhpUndefinedVariableInspection */
                        if ( in_array($val['SERIALNO'], $serialnumbers) || in_array($val['SERIALNO'], $consumedSerialNumbers)) {
                            $msg = "Serial number: '".$val['SERIALNO']."' assigned to Item: '".$val['ITEMID']."' in Line# ".($val['ITEMLINENO']+1)." already exists ".$docMsg;
                            $gErr->addIAError(
                                $errorCodeCase1, __FILE__ . ':' . __LINE__,
                                $msg, array_merge($placeholder, ['VAL_SERIALNO' => $val['SERIALNO'], 'VAL_ITEMID' => $val['ITEMID'], 'VAL_ITEMLINENO' => ($val['ITEMLINENO']+1)])
                            );
						} else {
							$msg = "Serial number: '".$val['SERIALNO']."' assigned to Item: '".$val['ITEMID']."' in Line# ".($val['ITEMLINENO']+1)." does not exist ".$docMsg;
							$gErr->addIAError(
							    $errorCodeCase2, __FILE__ . ':' . __LINE__,
							    $msg, array_merge($placeholder, ['VAL_SERIALNO' => $val['SERIALNO'], 'VAL_ITEMID' => $val['ITEMID'], 'VAL_ITEMLINENO' => ($val['ITEMLINENO']+1)])
							);
						}
						$ok=false;
					}
				}
			}
			
			return $ok;
		} // -------------- converting end ------------//

		//when purchase is having duplicate serial numbers
		$entrySerialNos = array();
        foreach( $trackingInfo as $val)	{
            if ( StkitDocumentManager::isStockableKitComponentTrackingEnabled() ) {
                if ( ( isset($val['COMPONENTID']) || $val['ITEMID'] != $entry['ITEMID'] )
                     && ( $values['DOCPARID'] == StkitDocumentManager::BUILDKIT
                          || $values['DOCPARID'] == StkitDocumentManager::DISKIT ) ) {
                    // This is a tracked SK component--no need to check their duplicate serial numbers here
                    continue;
                }
            }

			// collect serial numbers to check for validating in later part
            $entrySerialNos[] = $val['SERIALNO'];

			if($ok && $this->_action == EDIT_ACTION && is_array($this->_serialTrackingDetails) ){
				// --- ### $this->_serialTrackingDetails should be changed and we should be able to get the same details by calling GetSerialTrackingDetails_OldDoc
				//serialTrackingDetails = $this->GetSerialTrackingDetails_OldDoc($values['RECORDNO']);
				$orgSerialTrackingDetails = $this->_serialTrackingDetails[$itemid][$val['SERIALNO']];
				if(isset($orgSerialTrackingDetails['CHILD_DETAILS'])){
					$prevWhsekey	= $orgSerialTrackingDetails['WHSEKEY'];
					$newWhsekey		= $whsekey;

					if($newWhsekey != $prevWhsekey && $val['SERIALNO']==$orgSerialTrackingDetails['CHILD_DETAILS']['SERIALNO'] ){
						$msg = "Serial number '".$val['SERIALNO']."' assigned to Item '".$val['ITEMID']."' in Line# ".($val['ITEMLINENO']+1)." is already consumed by other documents";
						$gErr->addIAError(
						    'INV-1051', __FILE__ . ':' . __LINE__,
						    "Changing Warehouse from '" . $prevWhsekey . "' to '" . $newWhsekey . "' is not allowed", ['PREV_WHSEKEY' => $prevWhsekey, 'NEW_WHSEKEY' => $newWhsekey],
						    $msg, ['VAL_SERIALNO' => $val['SERIALNO'], 'VAL_ITEMID' => $val['ITEMID'], 'VAL_ITEMLINENO' => ($val['ITEMLINENO']+1)]
						);
						$ok=false;
					}
				}
			}
		}

        //
		// validating duplicate serial numbers
		// the serial numbers must be unique across the item irespective of ware house.
		if(
			(!empty($entrySerialNos))
            && ($values['DOCPARID'] !== ICTransferManager::INDOCTYPE) //We don't need to check for duplicate SN on Transfer document
			&& (
				$trackParams['AFFECTS_ONHAND_QTY'] 
				|| ($trackParams['AFFECTS_ONHAND_VALUE_ONLY'] && $recalledID == '')
			)
		) {
            $trackedSKFilter = "";
            if ( StkitDocumentManager::isStockableKitTrackingEnabled() ) {
                $trackedSKFilter = "AND NOT ( dh.state IN ('C') AND dh.docparkey IN (
                    SELECT dp.record# from docpar dp where dp.cny# = dh.cny# AND dp.docid = 'Build Kits'))";
            }
			$duplicateSerialNoQry[0] = "SELECT dh.docid, dec.serialno FROM docentrycost dec
									INNER JOIN docentrymst de ON de.cny# = dec.cny# AND de.record# = dec.docentrykey
									INNER JOIN dochdrmst dh ON dh.cny# = de.cny# AND dh.record# = de.dochdrkey AND dh.state NOT IN ('I','S','A', 'X', 'R') $trackedSKFilter
									INNER JOIN docparmst dp ON dp.cny# = dh.cny# AND dp.record# = dh.docparkey 
									INNER JOIN docpartotals dpt ON dpt.cny# = dp.cny# AND dpt.docparkey = dp.record# AND dpt.SIGN = 1
									INNER JOIN ictotal ict ON ict.cny# = dpt.cny# AND ict.record# = dpt.totalkey AND ict.NAME = 'ONHAND'
									WHERE dec.cny#  = :1
									AND dec.affects_inventory IN ('Q', 'QV')
									AND (dec.qtyleft != 0 OR dec.qtyleft is NULL)
									AND dec.itemkey = :2";

            $duplicateSerialNoQry[1] = $cny;
            $duplicateSerialNoQry[2] = $itemid;
            // in edit mode skip checking/validating the current document
            self::addDocumentAndWarehouseFiltersIfNeeded($duplicateSerialNoQry, $this->_action == EDIT_ACTION,
                                                         $trackParams['AFFECTS_ONHAND_VALUE_ONLY'] && $recalledID = '',
                                                         $trackParams['DOCID'], $whsekey);

            $duplicateSerialNoQry = PrepINClauseStmt($duplicateSerialNoQry, $entrySerialNos, " AND dec.serialno ", false, 'dummy', true);
            $rows = QueryResult($duplicateSerialNoQry);

			//
			// if the current document is affecting OnHand Quantity / Quantity & Value
			// either it is created directly or converted
			// if the serial number already exists in the inventory
			if ((!empty($rows)) && $trackParams['AFFECTS_ONHAND_QTY']) {
				$msg = "Serial number '" . $rows[0]['SERIALNO'] . "' assigned to Item '" . $itemid . "' in Line# " . ($lineNo+1) . " already exists in the Document '" . $rows[0]['DOCID'] . "'";
				$gErr->addIAError(
				    'INV-1052', __FILE__ . ':' . __LINE__,
				    "Duplicate Serial Number", [],
				    $msg, ['ROWS_0_SERIALNO' => $rows[0]['SERIALNO'], 'ITEMID' => $itemid, 'LINE_NO' => ($lineNo+1), 'ROWS_0_DOCID' => $rows[0]['DOCID']]
				);
				$ok = false;
			}

		} // ---- ENDS : validating duplicate serial numbers

//
        // Duplicate Invoice check
        // if ONHAND value only is affecting
        // check if there is any document impacting value exist for the same serial number.
        // duplicate vendor invoice (or any document affecting ONHand Value or Quantity & Value is not allowed)
        if(
            (!empty($entrySerialNos))
            && ($values['DOCPARID'] !== ICTransferManager::INDOCTYPE) //We don't need to check for duplicate SN on Transfer document
            && $trackParams['AFFECTS_ONHAND_VALUE']
        ) {
            $duplicateInvoiceQry[0] = "SELECT dh.docid, dec.serialno FROM docentrycost dec
									INNER JOIN docentrymst de ON de.cny# = dec.cny# AND de.record# = dec.docentrykey
									INNER JOIN dochdrmst dh ON dh.cny# = de.cny# AND dh.record# = de.dochdrkey AND dh.state NOT IN ('I','S','A', 'X', 'R')
									INNER JOIN docparmst dp ON dp.cny# = dh.cny# AND dp.record# = dh.docparkey AND dp.sale_pur_trans = 'P'
									INNER JOIN docpartotals dpt ON dpt.cny# = dp.cny# AND dpt.docparkey = dp.record# AND dpt.SIGN = 1
									INNER JOIN ictotal ict ON ict.cny# = dpt.cny# AND ict.record# = dpt.totalkey AND ict.NAME = 'ONHAND'
									WHERE dec.cny#  = :1
									AND dec.affects_inventory IN ('V', 'QV')
									AND dec.itemkey = :2
									AND (dec.qtyleft != 0 OR dec.qtyleft is NULL)
									AND dec.quantity > 0";

            $duplicateInvoiceQry[1] = $cny;
            $duplicateInvoiceQry[2] = $itemid;

            $bind = 2;
            if ($this->_action == EDIT_ACTION) {
                // in edit mode skip checking/validating the current document
                $duplicateInvoiceQry[0].= " AND dh.docid != :".++$bind;
                $duplicateInvoiceQry[] = $trackParams['DOCID'];
            }

            $duplicateInvoiceQry[0].= " AND dec.whsekey = :".++$bind;
            $duplicateInvoiceQry[] = $whsekey;

            if ($recalledID != '' && (!empty($parentInfo) && $parentInfo['AFFECTS_ONHAND_QTY'])) {
                $duplicateInvoiceQry[0].= " AND dh.docid != :".++$bind;
                $duplicateInvoiceQry[] = $recalledID;
            }

            $duplicateInvoiceQry = PrepINClauseStmt($duplicateInvoiceQry, $entrySerialNos, " AND dec.serialno ", false, 'dummy', true);
            $invRows = QueryResult($duplicateInvoiceQry);

            if ((!empty($invRows))) {
                /** @noinspection PhpUndefinedVariableInspection */
                $msg = sprintf('Serial number \'%1$s\' assigned to Item \'%2$s\' in Line# %3$s already Invoiced with the Document \'%4$s\'', $invRows[0]['SERIALNO'], $itemid, ($lineNo + 1), $invRows[0]['DOCID']);
                $gErr->addIAError(
                    'INV-1053', __FILE__ . ':' . __LINE__,
                    "Duplicate Serial Number", [],
                    $msg, ['INV_ROWS_0_SERIALNO' => $invRows[0]['SERIALNO'], 'ITEMID' => $itemid, 'LINE_NO' => ($lineNo + 1), 'INV_ROWS_0_DOCID' => $invRows[0]['DOCID']]
                );
                $ok = false;
            }

        } // ---- ENDS : validating duplicate invoice for same serial numbers


		return $ok;
	}

    /**
     * @param array $values
     * @param array $entry
     * @param array $trackingInfo
     *
     * @return bool
     */
    function ValidateSerialTracking_SalesReturn(&$values, $entry, &$trackingInfo){
		$gManagerFactory = Globals::$g->gManagerFactory;
		$gErr = Globals::$g->gErr;

		// $trackingInfo -- is the array
		$trackParams = $this->_trackParams;
		$ok = true;
		$cny			= GetMyCompany();
		$whsekey		= $entry['WAREHOUSE']['LOCATION_NO'];
		$recalledID		= $entry['SOURCE_DOCID'];
		$docDate		= $values['WHENCREATED'];
		$docentrycostMgr = $gManagerFactory->getManager('documententrycost');
        $tobeReturnSerialNumbers = [];

        $parentInfo = [];
        if (isset($entry['SOURCE_DOCKEY']) && $entry['SOURCE_DOCKEY'] != '') {
            $parentInfo = $trackParams['PARENTINFO'][$entry['SOURCE_DOCKEY']];
        }

		if(isset($trackingInfo)){
			$itemid = $trackingInfo[0]['ITEMID'];
		}else{
			$itemid	= $entry['ITEMID'];
		}

        // if purchase return is affecting value only
        // and if it is created directly
        if($recalledID =='' && $trackParams['ISSALES_RETURN'] && $trackParams['AFFECTS_ONHAND_VALUE']){
            $ok = $ok && $this->ValidateSerialTracking_SalesReturns_ValueOnly($values, $entry, $trackingInfo);
            return $ok;
        }

		if($trackParams['ISSALES_RETURN']){
			if ($recalledID!=''){
				$qry = 'QRY_DOCUMENTENTRYCOST_SELECT_DOCID';
                if (!empty($parentInfo)
                    && $parentInfo['AFFECTS_ONHAND_QTY']
                    && ($parentInfo['IN_OUT'] != $trackParams['IN_OUT'] || $trackParams['ISBACKORDER'])
                ) {
					$args = array($itemid,$recalledID,$cny);
				} else {
                    // use the $entry[SOURCE_DOCLINEKEY] to fetch the parent or source document up in the hierarchy
                    // using the getParentWithSerial
                    $sourceDocIDWithTrackingInfo = $this->getParentWithSerial($entry['SOURCE_DOCLINEKEY']);
					$args = array($itemid,$sourceDocIDWithTrackingInfo,$cny);
				}
			}else{
				$qry = 'QRY_DOCUMENTENTRYCOST_SELECT_AVAIL_SERIALNO_SALESRETURN';
				$args = array($itemid,$whsekey,$docDate,$cny);
			}
			$res = $docentrycostMgr->DoQuery($qry,$args);
            $returnedSerialNumbers = [];

            foreach( $res as $row){
			    $tempReturnSerialnumbers[$row['SERIALNO']] = $row;
				if($row['QTYLEFT'] > 0){
					$tobeReturnSerialNumbers[] = $row['SERIALNO'];
				}else{
					$returnedSerialNumbers[] = $row['SERIALNO'];
				}
			}

            foreach( $trackingInfo as $val){
				if(isset($val['SERIALNO'])){
                    /** @noinspection PhpUndefinedVariableInspection */
                    if ( $this->_action == EDIT_ACTION && in_array($val['SERIALNO'], $returnedSerialNumbers)){
				        $tobeReturnSerialNumbers[] = $val['SERIALNO'];
                    }
				    
					// if the serial number is not found in the array
					// either it would have alredy been returned or doesnt exist
                    /** @noinspection PhpUndefinedVariableInspection */
                    if (!in_array($val['SERIALNO'], $tobeReturnSerialNumbers)){
                        $sourceDocIDWithTrackingInfo = $this->getParentWithSerial($entry['SOURCE_DOCLINEKEY']);
                        $docMsg1 = $sourceDocIDWithTrackingInfo != '' ? $sourceDocIDWithTrackingInfo . " >> " : '';
                        $docMsg = "";
                        $placeholder = [];
                        $errorCode = 'INV-1098';
                        if($recalledID != ''){
                            $docMsg = "in '" . $docMsg1 . $recalledID . "'";
                            $errorCode = 'INV-1099';
                            $placeholder = ['DOC_MSG' => $docMsg1 . $recalledID];
                        }

						$qry = 'QRY_DOCUMENTENTRYCOST_DOCTYPE_SERIALNO';
						$args = array($cny, $val['SERIALNO'], $val['ITEMID'], $trackParams['DOCID'], $cny);
						$row = $docentrycostMgr->DoQuery($qry,$args);

						if((!empty($row))){
						    if($row[0]['DOCID'] == $trackParams['DOCID']){
						        $docTrack = "current document";
						        $placeholder = [];
						        $errorCode = 'INV-1097';
						    }else{
						        $docTrack = "Document '".$row[0]['DOCID']."'";
						        $placeholder = ['ROW_0_DOCID' => $row[0]['DOCID']];
						        $errorCode = 'INV-1096';
						    }
							$msg = "Serial number '".$val['SERIALNO']."' is already consumed by the ".$docTrack." for the Item '".$val['ITEMID']."'.";
							$gErr->addIAError(
							    $errorCode, __FILE__ . ':' . __LINE__,
							    "Unable to save Document", [],
							    $msg, array_merge($placeholder,['VAL_SERIALNO' => $val['SERIALNO'], 'VAL_ITEMID' => $val['ITEMID']])
						    );
						}else{
							$msg = "Serial number '".$val['SERIALNO']."' assigned to Item '".$val['ITEMID']."' in Line# ".($val['ITEMLINENO']+1)." is not available ".$docMsg.".";
							$gErr->addIAError(
							    $errorCode, __FILE__ . ':' . __LINE__,
							    "Unable to save Document", [],
							    $msg, array_merge($placeholder,['VAL_SERIALNO' => $val['SERIALNO'], 'VAL_ITEMID' => $val['ITEMID'], 'VAL_ITEMLINENO' => ($val['ITEMLINENO']+1)])
							);
						}
						$ok=false;
					} else {
                        if ($recalledID!=''){
                            $qry = 'QRY_DOCUMENTENTRYCOST_RETURN_DUPLICATE';
                            $args = array( $cny, $val['ITEMID'], $val['SERIALNO'], $recalledID );
                            $row = $docentrycostMgr->DoQuery($qry,$args);
                            if((!empty($row))){
                                if($row[0]['DOCID']!=''){
                                    $docMsg = "in '".$row[0]['DOCID']."'";
                                    $errorCode = 'INV-1073';
                                    $placeholder = ['VAL_SERIALNO' => $val['SERIALNO'], 'VAL_ITEMID' => $val['ITEMID'], 'VAL_ITEMLINENO' => ($val['ITEMLINENO']+1), 'DOCID' => $row[0]['DOCID']];
                                }else{
                                    $docMsg = ".";
                                    $errorCode = 'INV-1054';
                                    $placeholder = ['VAL_SERIALNO' => $val['SERIALNO'], 'VAL_ITEMID' => $val['ITEMID'], 'VAL_ITEMLINENO' => ($val['ITEMLINENO']+1)];
                                }
                                $msg = "Serial number: '".$val['SERIALNO']."' assigned to Item: '".$val['ITEMID']."' in Line# ".($val['ITEMLINENO']+1)." already exists ".$docMsg;
                                $gErr->addIAError(
                                    $errorCode, __FILE__ . ':' . __LINE__,
                                    "Unable to save Document", [],
                                    $msg, $placeholder
                                );
                                $ok=false;
                            }
                        }
                    }
				}
			}

		} // ------- sales return end ------------- //

		return $ok;
	}

    /**
     * @param array $values
     * @param array $entry
     * @param array $trackingInfo
     *
     * @return bool
     */
    function ValidateSerialTracking_SalesReturns_ValueOnly(
        /** @noinspection PhpUnusedParameterInspection */ &$values, $entry, &$trackingInfo)
    {
        $gErr = Globals::$g->gErr;

        // $trackingInfo -- is the array
        $trackParams = $this->_trackParams;
        $ok = true;
        $cny = GetMyCompany();
        $whsekey = $entry['WAREHOUSE']['LOCATION_NO'];
        $recalledID = $entry['SOURCE_DOCID'];

        if($recalledID!='' || !$trackParams['AFFECTS_ONHAND_VALUE']){
            return true;
        }

        if (isset($trackingInfo)) {
            $itemid = $trackingInfo[0]['ITEMID'];
        } else {
            $itemid = $entry['ITEMID'];
        }

        // for a po return value only
        // make sure there is a PO return for the same serial number
        // and multiple
        $entrySerialNos = [];
        foreach( $trackingInfo as $val)	{
            $entrySerialNos[] = $val['SERIALNO'];
        }

        if( (!empty($entrySerialNos))) {
            $duplicateReturnQry[0] = "SELECT dh.docid, dec.serialno, dec.affects_inventory FROM docentrycost dec
									INNER JOIN docentrymst de ON de.cny# = dec.cny# AND de.record# = dec.docentrykey
									INNER JOIN dochdrmst dh ON dh.cny# = de.cny# AND dh.record# = de.dochdrkey AND dh.state NOT IN ('I','S','A', 'X', 'R')
									INNER JOIN docparmst dp ON dp.cny# = dh.cny# AND dp.record# = dh.docparkey AND dp.sale_pur_trans = 'S'
									INNER JOIN docpartotals dpt ON dpt.cny# = dp.cny# AND dpt.docparkey = dp.record# AND dpt.SIGN = 1
									INNER JOIN ictotal ict ON ict.cny# = dpt.cny# AND ict.record# = dpt.totalkey AND ict.NAME = 'ONHAND'
									WHERE dec.cny#  = :1
									AND dec.qtyleft > 0
									AND dec.itemkey = :2";

            $duplicateReturnQry[1] = $cny;
            $duplicateReturnQry[2] = $itemid;
            // in edit mode skip checking/validating the current document
            self::addDocumentAndWarehouseFiltersIfNeeded($duplicateReturnQry, $this->_action == EDIT_ACTION, true,
                                                         $trackParams['DOCID'], $whsekey);

            $duplicateReturnQry = PrepINClauseStmt($duplicateReturnQry, $entrySerialNos, " AND dec.serialno ", false, 'dummy', true);
            $invRows = QueryResult($duplicateReturnQry);

            if (Util::countOrZero($invRows) == 0) {
                $slNos = implode(",", $entrySerialNos);
                /** @noinspection PhpUndefinedVariableInspection */
                $msg = "Could not find any return document with Serial numbers $slNos assigned to Item '" . $itemid . "' in Line# " . ( $lineNo + 1);
                $gErr->addIAError(
                    'INV-1055', __FILE__ . ':' . __LINE__,
                    "Return document not found", [],
                    $msg, ['SL_NOS' => $slNos, 'ITEMID' => $itemid, 'LINE_NO' => ($lineNo + 1)]
                );
                return false;
            }

            foreach($invRows as $returnDoc){
                if($returnDoc['AFFECTS_INVENTORY'] === 'V' || $returnDoc['AFFECTS_INVENTORY'] === 'QV'){
                    $returnDocid = $returnDoc['DOCID'];
                    /** @noinspection PhpUndefinedVariableInspection */
                    $msg = "A return document '$returnDocid' already exists for Serial number '" . $returnDoc['SERIALNO'] . "' assigned to Item '" . $itemid . "' in Line# " . ( $lineNo + 1);
                    $gErr->addIAError(
                        'INV-1056', __FILE__ . ':' . __LINE__,
                        "Return document exists", [],
                        $msg, ['RETURN_DOCID' => $returnDocid, 'RETURN_DOC_SERIALNO' => $returnDoc['SERIALNO'], 'ITEMID' => $itemid, 'LINE_NO' => ($lineNo + 1)]
                    );
                    return false;
                }
            }
        } // ---- ENDS : validating duplicate invoice for same serial numbers

        return $ok;
    }

    /**
     * @param array $values
     * @param array $entry
     * @param array $trackingInfo
     *
     * @return bool
     */
    function ValidateSerialTracking_Sales_ValueOnly(
        /** @noinspection PhpUnusedParameterInspection */ &$values, $entry, &$trackingInfo)
    {
        $gErr = Globals::$g->gErr;

        // $trackingInfo -- is the array
        $trackParams = $this->_trackParams;
        $ok = true;
        $cny = GetMyCompany();
        $whsekey = $entry['WAREHOUSE']['LOCATION_NO'];
        $recalledID = $entry['SOURCE_DOCID'];

        if($recalledID!='' || !$trackParams['AFFECTS_ONHAND_VALUE_ONLY']){
            return true;
        }

        if (isset($trackingInfo)) {
            $itemid = $trackingInfo[0]['ITEMID'];
        } else {
            $itemid = $entry['ITEMID'];
        }

        // for a po return value only
        // make sure there is a PO return for the same serial number
        // and multiple
        $entrySerialNos = [] ;
        foreach( $trackingInfo as $val)	{
            $entrySerialNos[] = $val['SERIALNO'];
        }

        if( (!empty($entrySerialNos))) {
            $duplicateInvoiceQry[0] = "SELECT dh.docid, dec.serialno, dec.affects_inventory FROM docentrycost dec
									INNER JOIN docentrymst de ON de.cny# = dec.cny# AND de.record# = dec.docentrykey
									INNER JOIN dochdrmst dh ON dh.cny# = de.cny# AND dh.record# = de.dochdrkey AND dh.state NOT IN ('I','S','A', 'X', 'R')
									INNER JOIN docparmst dp ON dp.cny# = dh.cny# AND dp.record# = dh.docparkey 
									INNER JOIN docpartotals dpt ON dpt.cny# = dp.cny# AND dpt.docparkey = dp.record# AND dpt.SIGN = 1
									INNER JOIN ictotal ict ON ict.cny# = dpt.cny# AND ict.record# = dpt.totalkey AND ict.NAME = 'ONHAND'
									WHERE dec.cny#  = :1
									AND dec.affects_inventory IN ('Q', 'QV')
									AND dec.qtyleft > 0
									AND dec.itemkey = :2";

            $duplicateInvoiceQry[1] = $cny;
            $duplicateInvoiceQry[2] = $itemid;
            // in edit mode skip checking/validating the current document
            self::addDocumentAndWarehouseFiltersIfNeeded($duplicateInvoiceQry, $this->_action == EDIT_ACTION, true,
                                                         $trackParams['DOCID'], $whsekey);

            $duplicateReturnQry = PrepINClauseStmt($duplicateInvoiceQry, $entrySerialNos, " AND dec.serialno ", false, 'dummy', true);
            $invRows = QueryResult($duplicateReturnQry);

            if (Util::countOrZero($invRows) == 0) {
                $slNos = implode(",", $entrySerialNos);
                /** @noinspection PhpUndefinedVariableInspection */
                $msg = "Serial numbers $slNos assigned to Item '" . $itemid . "' in Line# " . ( $lineNo + 1) . " is not available in warehouse " . $whsekey;
                $gErr->addIAError(
                    'INV-1057', __FILE__ . ':' . __LINE__,
                    "Serial number not found", [],
                    $msg, ['SL_NOS' => $slNos, 'ITEMID' => $itemid, 'LINE_NO' => ($lineNo + 1), 'WHSEKEY' => $whsekey]
                );
                return false;
            }else{
                foreach($invRows as $row){
                    $availSerialNumbers[] = $row['SERIALNO'];
                }

                foreach( $entrySerialNos as $eSerialNo){
                    /** @noinspection PhpUndefinedVariableInspection */
                    if (!in_array($eSerialNo, $availSerialNumbers)){
                        /** @noinspection PhpUndefinedVariableInspection */
                        $msg = "Serial number '" . $eSerialNo . "' assigned to Item '" . $itemid . "' in Line# " . ( $lineNo + 1) . " is not available in warehouse '" . $whsekey . "'";
                        $gErr->addIAError(
                            'INV-1058', __FILE__ . ':' . __LINE__,
                            "Serial number not found", [],
                            $msg, ['E_SERIAL_NO' => $eSerialNo, 'ITEMID' => $itemid, 'LINE_NO' => ($lineNo + 1), 'WHSEKEY' => $whsekey]
                        );
                        $ok = false;
                    }
                }

            }
        } // ---- ENDS : validating duplicate invoice for same serial numbers

        return $ok;
    }

    /**
     * @param array $values
     * @param array $trackingInfo
     * @param string $inOut
     * @param array $entry
     *
     * @return bool
     */
	public function ValidateSerialNumberExpiration(&$values, &$trackingInfo, $inOut,$entry)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;
        $docDate = $values['WHENCREATED'];
        $containsOnHandSubtract = function($invTotals){
            if (is_array($invTotals)){
                foreach($invTotals as $invTotal){
                    if ($invTotal['TOTALID'] === 'ONHAND' && $invTotal['SIGN'] === 'Subtract'){
                        return true;
                    }
                }
            }
            return false;
        };

        $isOnHandSubTrans = $containsOnHandSubtract($values['_DOCPAR']['DOCPAR_TOTALS']);

        foreach ($trackingInfo as $tkey) {
            $isExpirationTrackedComponentForBuild = false;
            if ( StkitDocumentManager::isStockableKitComponentTrackingEnabled()
                 && $values['DOCPARID'] == StkitDocumentManager::BUILDKIT ) {
                if ( isset($tkey['COMPONENTID']) && ( $tkey['COMPONENTID'] != '' ) ) {
                    if ( $this->isItemEnabledForTracking($tkey['COMPONENTID'], SERIALNO_ENABLED)
                         && $this->isItemEnabledForTracking($tkey['COMPONENTID'], EXPIRATION_ENABLED) ) {
                        $isExpirationTrackedComponentForBuild = true;
                    } else {
                        // Component is not expiration tracked--shouldn't be validated here at all, so skip it
                        continue;
                    }
                } else {
                    if ( ! $this->isItemEnabledForTracking($tkey['ITEMID'], SERIALNO_ENABLED)
                         || ! $this->isItemEnabledForTracking($tkey['ITEMID'], EXPIRATION_ENABLED) ) {
                        continue;
                    }
                }
            }
            if (!$this->isItemEnabledForTracking($tkey['ITEMID'], SERIALNO_ENABLED) ||
                !$this->isItemEnabledForTracking($tkey['ITEMID'], EXPIRATION_ENABLED)) {
                // No expiration to validate for this tracking specification
                continue;
            }
            $expDate = $tkey['EXPIRATION'];

            if($isOnHandSubTrans) {
                $sourceExpDateMatch = true;     // check the user entered exp .date of the line item against the cost source exp. date
                $res = $this->getSourceLayerExpiryDate($tkey['ITEMID'], $entry['WAREHOUSEID'], $tkey['SERIALNO']);
                if(is_array($res)) {
                    $sourceExpiryDate = $res[0]['EXPIRATIONDATE'];
                    if (DateCompare($sourceExpiryDate, $expDate) != 0) {
                        $sourceExpDateMatch = false;
                    }
                }
                if(!$sourceExpDateMatch) {
                    $UILineNo = $tkey['ITEMLINENO'] + 1;
                    $msg = "The expiry date '{$expDate}' of the Item '{$tkey['ITEMID']}' with the Serial Number '{$tkey['SERIALNO']}'"
                        ." in Line# '$UILineNo' does not match the source expiration date '{$sourceExpiryDate}'";
                    $errorCode = 'INV-1460';
                    $placeholder = ['EXP_DATE'       => $expDate, 'TKEY_ITEMID' => $tkey['ITEMID'],'TKEY_SERIALNO'  => $tkey['SERIALNO'],
                         'TKEY_UI_LINENO' => $UILineNo, 'SOURCE_EXP_DATE' => $sourceExpiryDate];
                    $gErr->addIAError($errorCode, __FILE__.':'.__LINE__, "Unable to save document", [], $msg, $placeholder);

                    return false;
                }
            }

            if (!($isOnHandSubTrans && $values['_DOCPAR']['SALE_PUR_TRANS'] === "Internal")) { //if not the internal adjust out , check if the line item has expired
                $dateDiff = DateCompare($expDate, $docDate);
                if ($dateDiff == -1 || $dateDiff == 0) {
                    if ($inOut === 'Decrease' || $isExpirationTrackedComponentForBuild) {
                        $msg = "The Serial Number '".$tkey['SERIALNO']."' for the Item '".$tkey['ITEMID']
                               ."' in Line# ".($tkey['ITEMLINENO'] + 1)." has expired on ".$expDate
                               .". Please select another serial number";
                        $errorCode = 'INV-1090';
                        $placeholder = ['TKEY_SERIALNO'   => $tkey['SERIALNO'], 'TKEY_ITEMID' => $tkey['ITEMID'],
                                        'TKEY_ITEMLINENO' => ($tkey['ITEMLINENO'] + 1), 'EXP_DATE' => $expDate];
                    } else {
                        $msg = "The Serial Number '".$tkey['SERIALNO']."' for the Item '".$tkey['ITEMID']
                               ."' in Line# ".($tkey['ITEMLINENO'] + 1)." has expired on ".$expDate.".";
                        $errorCode = 'INV-1091';
                        $placeholder = ['TKEY_SERIALNO'   => $tkey['SERIALNO'], 'TKEY_ITEMID' => $tkey['ITEMID'],
                                        'TKEY_ITEMLINENO' => ($tkey['ITEMLINENO'] + 1), 'EXP_DATE' => $expDate];
                    }
                    $gErr->addIAError($errorCode, __FILE__.':'.__LINE__, "Unable to save document", [], $msg,
                                      $placeholder);
                    $ok = false;
                }
            }
        }

        return $ok;
    }

    /**
     * @param string $itemID
     * @param string $warehouseID
     * @param string $serialNo
     * @param string $lotNo
     * Get the source layer's expiry date for the serial or lot item
     * @return array|bool
     */

    public function getSourceLayerExpiryDate(string $itemID,string $warehouseID,string $serialNo='',string $lotNo='') : array|bool
    {
        $stmt = array();
        $stmt[] = "SELECT
                    dec.record# as COSTKEY,
                    dec.itemkey as ITEMKEY,
                    dec.serialno as SERIALNO,
                    dec.lotno as LOTNO,
                    dec.expirationdate as EXPIRATIONDATE
                FROM
                    docentrycost dec
                    INNER JOIN docentrymst de ON de.cny# = dec.cny#  AND de.record# = dec.docentrykey
                    INNER JOIN dochdrmst dh ON dh.cny# = de.cny# AND dh.record# = de.dochdrkey AND dh.state NOT IN ('I','S','A','X','R' )
                WHERE
                    dec.cny# =:1
                    AND dec.whsekey =:2
                    AND dec.in_out = 'I'
                    AND dec.affects_inventory IN ('V','QV') 
                    AND dec.itemkey=:3 ";

        $stmt[] = GetMyCompany();
        $stmt[] = $warehouseID;
        $stmt[] = $itemID;

        if (!empty($serialNo)) {
            $stmt[0] .= " AND dec.serialno = :4";
            $stmt[] = $serialNo;
        }elseif (!empty($lotNo)) {
            $stmt[0] .= " AND dec.lotno = :4";
            $stmt[] = $lotNo;
        }

        $stmt[0] .= " Order by dec.record# desc ";
        $res = QueryResult($stmt);
        return $res;
    }

	// ----------- Lot Tracking validation methods ---------------//
	//function ValidateLotTracking
    /**
     * @param array $values
     * @param array $entry
     * @param array $trackingInfo
     *
     * @return bool
     */
    function ValidateLotTracking(&$values, $entry, &$trackingInfo){
		$ok = true;
		$trackParams = $this->_trackParams;
		//
		// Purchase Create/Edit
		if ($trackParams['ISPURCHASE']){
			//Validating while creating/editing the purchase document for used lotnumbers in PO/INV
			$ok = $ok && $this->ValidateLotTracking_Purchase($values, $entry, $trackingInfo);

            //khiem 3/8/20: For future and similar to escalation 15869097 Build kit transaction errors on having a component
            //with expiration date. We need to implement and call a method ValidateLotTracking_BuildKits like in the
            //case of bin validation calling ValidateBinTracking_BuildKits
            // $isBuildKitTxn=$values['DOCPARID']==StkitDocumentManager::BUILDKIT;
            // if ($isBuildKitTxn) {
            //     $ok = $ok && $this->ValidateLotTracking_BuildKits($values, $entry, $trackingInfo);
            // }
		}
		//
		// Purchase return
		if ($trackParams['ISPURCHASE_RETURN']) {
			$ok = $ok && $this->ValidateLotTracking_PurchaseReturn($values, $entry, $trackingInfo);
		}
		//
		//If sales return
		if ($trackParams['ISSALES_RETURN']){
			$ok = $ok && $this->ValidateLotTracking_SalesReturn($values, $entry, $trackingInfo);
		}

		return $ok;
	}

    /**
     * Add filters as needed based on specified parameters.
     *
     * @param [] $query                       The array of query string and bind variables so far
     * @param string $isDocumentFilterNeeded  True if document id filter should be appended, false otherwise
     * @param string $isWarehouseFilterNeeded True if warehouse id filter should be appended, false otherwise
     * @param string $docId                   Document id to filter for
     * @param string $warehouseId             Warehouse id to filter for
     *
     * @return int                            The next bind index the caller should use
     */
    private static function addDocumentAndWarehouseFiltersIfNeeded(&$query, $isDocumentFilterNeeded, $isWarehouseFilterNeeded, $docId, $warehouseId) : int
    {
        // Determine the index of the next bind variable.
        $bindCount = count($query);

        if ($isDocumentFilterNeeded) {
            $query[0].= " AND dh.docid != :" . $bindCount++ . " ";
            $query[] = $docId;
        }

        if ($isWarehouseFilterNeeded) {
            $query[0].= " AND dec.whsekey = :" . $bindCount++ . " ";
            $query[] = $warehouseId;
        }

        return $bindCount;
    }

    /**
     * @param array $values
     * @param array $entry
     * @param array $trackingInfo
     *
     * @return bool
     */
    function ValidateLotTracking_Purchase(
        /** @noinspection PhpUnusedParameterInspection */ &$values, $entry, &$trackingInfo){
		$gManagerFactory = Globals::$g->gManagerFactory;
		$gErr = Globals::$g->gErr;

		$ok = true;
		$cny = GetMyCompany();
		$trackParams = $this->_trackParams;

        $existingEntry = $values['EXISTING_ENTRIES'][$entry['RECORDNO']] ?? []; // what the entry was

		// if 'value' only document comes with adj key then no need to validate. 
        // It is trying to adjust existing 'Value' layer
		if ($trackParams['AFFECTS_ONHAND_VALUE_ONLY'] && $entry['ADJDOCENTRYKEY']) {
			return true;
		}
		
        $recalledID	= $entry['SOURCE_DOCID'];
		$docentrycostMgr = $gManagerFactory->getManager('documententrycost');
		$whsekey	= $entry['WAREHOUSE']['LOCATION_NO'];

		if(isset($trackingInfo)){
			$itemid = $trackingInfo[0]['ITEMID'];
		}else{
			$itemid		= $entry['ITEMID'];
		}

		//Validating while creating/editing the purchase document for used lotnumbers in PO/INV
        $entryLotQuantities = array();
        foreach( $trackingInfo as $val)	{
			if($this->_action==EDIT_ACTION){
				// when a PO document is edited after the sales transactions consumed the quantity (sales documents have reference to the purchases).
				// Query to find the quantity left for PO document, such that the quantity edited should not be less than sale quantity
				$qryGetQtyleftOfPur = "QRY_DOCUMENTENTRYCOST_SELECT_PUR_QTYLEFT";
                $lineNo             = $existingEntry['LINE_NO'] ?? $entry['LINE_NO']; // get the original line number in case it was moved.
				$argGetQtyleftOfPur = array($cny,$trackParams['DOCID'],$val['LOTNO'], $lineNo);
				$GetQtyleftOfPur    = $docentrycostMgr->DoQuery($qryGetQtyleftOfPur,$argGetQtyleftOfPur);
				$QtyofParentDoc     = $GetQtyleftOfPur[0]['QUANTITY'] ?? 0;
				$QtyleftofParentDoc = $GetQtyleftOfPur[0]['QTYLEFT']  ?? 0;
                $minQuantity        = ($QtyofParentDoc - $QtyleftofParentDoc);

				if ($val['QUANTITY'] < $minQuantity) {
                    $lineNo++;
                    $msg = "For line $lineNo, item $itemid, you cannot lower the quantity below $minQuantity, which is the quantity that's been consumed by sales, adjustments, or transfers.";
					$gErr->addIAError(
                        'INV-1425', __FILE__ . ':' . __LINE__,
                        "Unable to edit the document - Invalid Quantity",[],
                        $msg, ['LINE_NO' => $lineNo, 'ITEMID' => $itemid, 'MIN_QUANTITY' => $minQuantity]
                    );
					return false;
				}

				if($ok){
					// --- ### this need to relooked. $this->_lotTrackingDetails is populated when a document is edited in documentmanager::set -> GetLOTTrackingDetails()
					// --- ### need to prepare here not in the DocumentManager.
					// --- ### $this->_lotTrackingDetails should be changed, and we should be able to get the same details by calling GetLotTrackingDetails_OldDoc
					//lotTrackingDetails = $this->GetLotTrackingDetails_OldDoc($values['RECORDNO']);
					$orgLotTrackingDetails = $this->_lotTrackingDetails[$itemid][$val['LOTNO']];
					if(isset($orgLotTrackingDetails['CHILD_DETAILS'])){
						$prevWhsekey	= $orgLotTrackingDetails['WHSEKEY'];
						$newWhsekey		= $whsekey;

						if($newWhsekey != $prevWhsekey && $val['LOTNO']==$orgLotTrackingDetails['CHILD_DETAILS']['LOTNO'] ){
							$msg = "Lot Number: '".$val['LOTNO']."' assigned to Item: '".$val['ITEMID']."' in Line# ".($val['ITEMLINENO']+1)." is used in other documents";
							$gErr->addIAError(
							    'INV-1060', __FILE__ . ':' . __LINE__,
							    "Changing Warehouse from '$prevWhsekey' to '$newWhsekey' is not allowed", ['PREV_WHSEKEY' => $prevWhsekey, 'NEW_WHSEKEY' => $newWhsekey],
							    $msg, ['VAL_LOTNO' => $val['LOTNO'], 'VAL_ITEMID' => $val['ITEMID'], 'VAL_ITEMLINENO' => ($val['ITEMLINENO']+1)]
							);
							return false;
						}
					}
				}
			}

			if($val['LOTNO']!=''){
                $entryLotQuantities[$val['LOTNO']] += $val['QUANTITY'];
			}
		}//foreach


		//
        // validating Lot number
        // the lot numbers must must exist in inventory for the given warehouse.
        $entryLotNumbers = array_keys($entryLotQuantities);
        if((!empty($entryLotNumbers)) && $trackParams['AFFECTS_ONHAND_VALUE_ONLY']) {
            $lotNoQry[0] = "SELECT dh.docid, dec.lotno, dec.quantity, dec.binkey, dec.aislekey, dec.rowkey FROM docentrycost dec
									INNER JOIN docentrymst de ON de.cny# = dec.cny# AND de.record# = dec.docentrykey
									INNER JOIN dochdrmst dh ON dh.cny# = de.cny# AND dh.record# = de.dochdrkey AND dh.state NOT IN ('I','S','A', 'X', 'R')
									INNER JOIN docparmst dp ON dp.cny# = dh.cny# AND dp.record# = dh.docparkey 
									INNER JOIN docpartotals dpt ON dpt.cny# = dp.cny# AND dpt.docparkey = dp.record# AND dpt.SIGN = 1
									INNER JOIN ictotal ict ON ict.cny# = dpt.cny# AND ict.record# = dpt.totalkey AND ict.NAME = 'ONHAND'
									WHERE dec.cny#  = :1
									AND dec.affects_inventory IN ('Q', 'QV')
									AND dec.itemkey = :2";

            $lotNoQry[1] = $cny;
            $lotNoQry[2] = $itemid;
            // in edit mode skip checking/validating the current document
            $bindCount = self::addDocumentAndWarehouseFiltersIfNeeded($lotNoQry, $this->_action == EDIT_ACTION, true,
                                                         $trackParams['DOCID'], $whsekey);

            if($recalledID!=''){
                $lotNoQry[0].= " AND dh.docid = :" . $bindCount . " ";
                $lotNoQry[] = $recalledID;
            }

            $lotNoQry = PrepINClauseStmt($lotNoQry, $entryLotNumbers, " AND dec.lotno ", false, 'dummy', true);
            $rows = QueryResult($lotNoQry);

            //
            // If document is affecting only ONHAND Value
            // and if it is created directly (with out converting from ONHAND Quantity affecting parent)
            // make sure the Lot number(s) exists in Inventory
            $availLotQuantities = array();
            if ($trackParams['AFFECTS_ONHAND_VALUE_ONLY']) {
                foreach( $rows as $row){
                    $availLotQuantities[$row['LOTNO']] += $row['QUANTITY'];
                }

                $availLotNumbers = array_keys($availLotQuantities);
                foreach( $entryLotNumbers as $eLotNo){
                    if (!in_array($eLotNo, $availLotNumbers)){
                    	if($recalledID!=''){
                            /** @noinspection PhpUndefinedVariableInspection */
                            $msg = "Lot number '" . $eLotNo . "' assigned to Item '" . $itemid . "' in Line# " . ( $lineNo + 1) . " is not available in parent document '" . $recalledID . "' and in warehouse '" . $whsekey . "'";
                            $errorCode = 'INV-1088';
                            $placeholder = ['E_LOT_NO' => $eLotNo, 'ITEMID' => $itemid, 'LINE_NO' => ($lineNo + 1), 'RECALLEDID' => $recalledID, 'WHSEKEY' => $whsekey];
						}else{
                            /** @noinspection PhpUndefinedVariableInspection */
                            $msg = "Lot number '" . $eLotNo . "' assigned to Item '" . $itemid . "' in Line# " . ( $lineNo + 1) . " is not available in warehouse '" . $whsekey . "'";
                            $errorCode = 'INV-1089';
                            $placeholder = ['E_LOT_NO' => $eLotNo, 'ITEMID' => $itemid, 'LINE_NO' => ($lineNo + 1), 'WHSEKEY' => $whsekey];
						}
                        $gErr->addIAError(
                            $errorCode, __FILE__ . ':' . __LINE__,
                            "Lot number not found", [],
                            $msg, $placeholder
                        );
                        return false;
                    }else{
                    	// if lot number exists then
                        // check if the quantity is more than available in the parent document
						if($recalledID!=''){
							$parentQty = $availLotQuantities[$eLotNo];
							$entryQty = $entryLotQuantities[$eLotNo];
							$diffQty = $parentQty - $entryQty;
							if($diffQty<0){
                                /** @noinspection PhpUndefinedVariableInspection */
                                $msg = "Lot number '" . $eLotNo . "' quantity exceed for Item '" . $itemid . "' in Line# " . ( $lineNo + 1) . " exceed the quantity in parent document '" . $recalledID . "' and in warehouse '" . $whsekey . "'";
                                $gErr->addIAError(
                                    'INV-1061', __FILE__ . ':' . __LINE__,
                                    "Lot number not found", [],
                                    $msg, ['E_LOT_NO' => $eLotNo, 'ITEMID' => $itemid, 'LINE_NO' => ($lineNo + 1), 'RECALLEDID' => $recalledID, 'WHSEKEY' => $whsekey]
                                );
                                return false;
							}
						}
					}
                }
            }

        } // ---- ENDS : validating lot numbers

        //
        // validating Lot number
        // the lot numbers quantities should not exceed than the IN quantity for the given warehouse.
        $entryLotNumbers = array_keys($entryLotQuantities);
        if((!empty($entryLotNumbers)) && $trackParams['AFFECTS_ONHAND_VALUE_ONLY']) {
            $lotQtyQry[0] = "SELECT 
							  dec.lotno, 
							  SUM( CASE WHEN dec.affects_inventory in ('V', 'QV') THEN dec.quantity ELSE 0 END) as tot_invoiced_qty,
							  SUM( CASE WHEN dec.affects_inventory in ('Q', 'QV') THEN dec.quantity ELSE 0 END) as tot_onhand_qty,
							  dec.expirationdate
							FROM docentrycost dec
							  INNER JOIN docentrymst de ON de.cny# = dec.cny# AND de.record# = dec.docentrykey
							  INNER JOIN dochdrmst dh ON dh.cny# = de.cny# AND dh.record# = de.dochdrkey AND dh.state NOT IN ('I','S','A', 'X', 'R')
							  INNER JOIN docparmst dp ON dp.cny# = dh.cny# AND dp.record# = dh.docparkey 
							  INNER JOIN docpartotals dpt ON dpt.cny# = dp.cny# AND dpt.docparkey = dp.record# AND dpt.SIGN = 1
							  INNER JOIN ictotal ict ON ict.cny# = dpt.cny# AND ict.record# = dpt.totalkey AND ict.NAME = 'ONHAND'
							WHERE dec.cny#  = :1
							  AND dec.itemkey = :2
							  AND dec.in_out = 'I'
							  AND dec.systemgenerated != 'T'
							";

            $lotQtyQry[1] = $cny;
            $lotQtyQry[2] = $itemid;
            
            $bind = 2;
            if ($this->_action == EDIT_ACTION) {
                // in edit mode skip checking/validating the current document
                $lotQtyQry[0].= " AND dh.docid != :".++$bind;
                $lotQtyQry[] = $trackParams['DOCID'];
            }

            $lotQtyQry[0].= " AND dec.whsekey = :".++$bind;
            $lotQtyQry[] = $whsekey;

            $lotQtyQry = PrepINClauseStmt($lotQtyQry, $entryLotNumbers, " AND dec.lotno ", false, 'dummy', true);
            $lotQtyQry[0].= " GROUP BY dec.lotno, dec.expirationdate";
            $rows = QueryResult($lotQtyQry);

            //
            // If document is affecting only ONHAND Value
            $availLotQuantities = array();
            foreach( $rows as $row){
				$availLotQuantities[$row['LOTNO']] = $row['TOT_ONHAND_QTY'] - ($row['TOT_INVOICED_QTY'] + $entryLotQuantities[$row['LOTNO']]);
			}

            foreach( $entryLotNumbers as $eLotNo){
				// check if the quantity is more than available in the parent document
				$totAvailQty = $availLotQuantities[$eLotNo];
				if($totAvailQty<0){
                    /** @noinspection PhpUndefinedVariableInspection */
                    $msg = sprintf('Total invoice quantities now exceed the total quantity in inventory for Lot number \'%1$s\' assigned to Item \'%2$s\' in Line# %3$s in warehouse \'%4$s\'', $eLotNo, $itemid, ($lineNo + 1), $whsekey);
					$gErr->addIAError(
					    'INV-1062', __FILE__ . ':' . __LINE__,
					    "Invoice quantities exceeding", [],
					    $msg, ['E_LOT_NO' => $eLotNo, 'ITEMID' => $itemid, 'LINE_NO' => ($lineNo + 1), 'WHSEKEY' => $whsekey]
					);
					return false;
				}
			}
        } // ---- ENDS : validating invoice quantities

        return $ok;
	}

    /**
     * @param array $values
     * @param array $entry
     * @param array $trackingInfo
     *
     * @return bool
     */
    function ValidateLotTracking_PurchaseReturn(
        /** @noinspection PhpUnusedParameterInspection */ &$values, $entry, &$trackingInfo){
		$gManagerFactory = Globals::$g->gManagerFactory;
		$gErr = Globals::$g->gErr;

		$ok = true;
		$cny = GetMyCompany();
		$trackParams = $this->_trackParams;
		$recalledID	= $entry['SOURCE_DOCID'];
		$whsekey	= $entry['WAREHOUSE']['LOCATION_NO'];
		$docentrycostMgr = $gManagerFactory->getManager('documententrycost');

        $parentInfo = [];
        if (isset($entry['SOURCE_DOCKEY']) && $entry['SOURCE_DOCKEY'] != '') {
            $parentInfo = $trackParams['PARENTINFO'][$entry['SOURCE_DOCKEY']];
        }

		if(isset($trackingInfo)){
			$itemid = $trackingInfo[0]['ITEMID'];
		}else{
			$itemid	= $entry['ITEMID'];
		}

		// if the document is converted from other document
		if ($recalledID!=''){
			$qryGetPurDetails	= 'QRY_DOCUMENTENTRYCOST_SELECT_AVAIL_PARENT_LOTNO';
            if (!empty($parentInfo) && $parentInfo['AFFECTS_ONHAND_QTY']) {
				$argsGetPurDetails	= array($itemid, $cny, $recalledID);
			}else{
				$parentWithLotNumbers = $this->getParentWithSerial($entry['SOURCE_DOCLINEKEY']);
				$argsGetPurDetails	= array($itemid, $cny, $parentWithLotNumbers);
			}
			$GetPurDetails = $docentrycostMgr->DoQuery($qryGetPurDetails,$argsGetPurDetails);
		}else{
			$qryGetPurDetails = "select record# doccomponentkey,lotno,qtyleft from docentrycost where itemkey = :1 and whsekey = :2 and in_out = 'I' and cny#=:3";
			$GetPurDetails = QueryResult(array($qryGetPurDetails,$itemid,$whsekey,$cny));
		}

        $polotnumbers = [];
        foreach( $GetPurDetails as $row){
			$polotnumbers[] = $row['LOTNO'];
			$temppolotnumbers[$row['LOTNO']] = $row;
		}

        foreach( $trackingInfo as $val){
			if(isset($val['LOTNO'])){
                if (!in_array($val['LOTNO'], $polotnumbers)){
					if ($recalledID){
						$msg = "The Lot number : '".$val['LOTNO']."' is not used by the item '".$val['ITEMID']."' in the parent document '".$recalledID."'. Please enter valid lot number.";
						$gErr->addIAError(
						    'INV-1063', __FILE__ . ':' . __LINE__,
						    "Unable to save document - Invalid Lot number", [],
						    $msg, ['VAL_LOTNO' => $val['LOTNO'], 'VAL_ITEMID' => $val['ITEMID'], 'RECALLEDID' => $recalledID]
						);
						$ok= false;
					}else{
						$msg = "The Lot number : '".$val['LOTNO']."'is not assigned to the item '".$val['ITEMID']."'. Please enter valid lot number.";
						$gErr->addIAError(
						    'INV-1064', __FILE__ . ':' . __LINE__,
						    "Unable to save document - Invalid Lot number", [],
						    $msg, ['VAL_LOTNO' => $val['LOTNO'], 'VAL_ITEMID' => $val['ITEMID']]
						);
						$ok= false;
					}
				}
			}
		}//foreach ends

		return $ok;
	}

    /**
     * @param array $values
     * @param array  $entry
     * @param array $trackingInfo
     *
     * @return bool
     */
    function ValidateLotTracking_SalesReturn(
        /** @noinspection PhpUnusedParameterInspection */ &$values, $entry, &$trackingInfo){
		$gManagerFactory = Globals::$g->gManagerFactory;
		$gErr = Globals::$g->gErr;

		$ok = true;
		$cny = GetMyCompany();
		$recalledID	= $entry['SOURCE_DOCID'];
		$whsekey	= $entry['WAREHOUSE']['LOCATION_NO'];
		$docentrycostMgr = $gManagerFactory->getManager('documententrycost');

		if(isset($trackingInfo)){
			$itemid = $trackingInfo[0]['ITEMID'];
		}else{
			$itemid	= $entry['ITEMID'];
		}

		if ($recalledID!=''){
            $qry = 'QRY_DOCUMENTENTRYCOST_SELECT_AVAIL_PARENT_SERIALNO';

            $sourceDocIDWithTrackingInfo = $this->getParentWithSerial($entry['SOURCE_DOCLINEKEY']);
            if ($sourceDocIDWithTrackingInfo != '') {
                $args = array($itemid, $whsekey, $cny, $sourceDocIDWithTrackingInfo);
            } else {
                $args = array($itemid, $whsekey, $cny, $recalledID);
            }

			$GetSaleDetails = $docentrycostMgr->DoQuery($qry,$args);
		}//if Recall info is there
		else{
			$qry = "select record# doccomponentkey,lotno,qtyleft from docentrycost where itemkey = :1 and whsekey = :2 and in_out 
						='O' and cny#=:3 order by record# asc";
			$GetSaleDetails = QueryResult(array($qry,$itemid,$whsekey,$cny));
		}

        foreach( $GetSaleDetails as $row){
			$solotnumbers[] = $row['LOTNO'];
			$tempsolotnumbers[$row['LOTNO']] = $row;
		}

        foreach ($trackingInfo as $val) {
            if (isset($val['LOTNO'])) {
                /** @noinspection PhpUndefinedVariableInspection */
                if (!in_array($val['LOTNO'], $solotnumbers ?? [])) {
					if ($recalledID==''){
						$msg = "The Lot number '".$val['LOTNO']."' is not consumed by any of the Sales Document . Please enter valid Lot number.";
						$gErr->addIAError(
						    'INV-1065', __FILE__ . ':' . __LINE__,
						    "Unable to save document - Invalid Lot Number", [],
						    $msg, ['VAL_LOTNO' => $val['LOTNO']]
						);
					}else{
						$msg = "The Lot number '".$val['LOTNO']."' is not consumed by the parent document '".$recalledID." '. Please enter valid lot number.";
						$gErr->addIAError(
						    'INV-1066', __FILE__ . ':' . __LINE__,
						    "Unable to save document - Invalid Lot Number", [],
						    $msg, ['VAL_LOTNO' => $val['LOTNO'], 'RECALLEDID' => $recalledID]
						);
					}
					$ok= false;
				}
			}
		}
		
		return $ok;
	}


	// ----------- Bin Tracking validation methods ---------------//
	// mostly cleaning is not required.
    /**
     * @param array $values
     * @param array $entry
     * @param array $trackingInfo
     *
     * @return bool
     */
    function ValidateBinTracking(&$values, $entry, &$trackingInfo){
		$ok = true;
		$trackParams = $this->_trackParams;

		// Purchase
		if($trackParams['ISPURCHASE']){
			$ok = $ok && $this->ValidateBinTracking_Purchase($values, $entry, $trackingInfo);

            $isBuildKitTxn=$values['DOCPARID']==StkitDocumentManager::BUILDKIT;
			if ($isBuildKitTxn) {
				$ok = $ok && $this->ValidateBinTracking_BuildKits($values, $entry, $trackingInfo);
			}
		}

		// validation logic for Sales / Purchase Return / Inv Transfer In:
		if ($trackParams['ISSALES'] || $trackParams['ISPURCHASE_RETURN']) {
			$ok = $ok && $this->ValidateBinTracking_Sales_PurchaseReturn($values, $entry, $trackingInfo);
		}

		// Sales Return
		if($trackParams['ISSALES_RETURN']){
			$ok = $ok && $this->ValidateBinTracking_SalesReturn($values, $entry, $trackingInfo);
		}

		return $ok;
	}

    /**
     * @param array $values
     * @param array $entry
     * @param array $trackingInfo
     *
     * @return bool
     */
    function ValidateBinTracking_Purchase(
        /** @noinspection PhpUnusedParameterInspection */ &$values, $entry, &$trackingInfo){
		$gErr = Globals::$g->gErr;
		$ok = true;
		$whsekey	= $entry['WAREHOUSE']['LOCATION_NO'];

		if(isset($trackingInfo)){
			$itemid = $trackingInfo[0]['ITEMID'];
		}else{
			$itemid		= $entry['ITEMID'];
		}

		if($this->_action == EDIT_ACTION){
			// $this->_binTrackingDetails should be changed and we should be able to get the same details by calling GetBinTrackingDetails_OldDoc
			// $binTrackingDetails = $this->GetBinTrackingDetails_OldDoc($values['RECORDNO']);
			if(isset($this->_binTrackingDetails[$itemid])){
                foreach( $trackingInfo as $track){
					$aislerowbinkey = $track['ITEMLINENO']."|".$track['AISLEID']."|".$track['ROWID']."|".$track['BINID']."|".$track['EXPIRATION'];

					$aisleid = $track['AISLEID'];
					$rowid = $track['ROWID'];
					$binid = $track['BINID'];

					$binMsg = $aisleid;
					$binMsg = ($rowid!='') ? ($binMsg!='' ? $binMsg ." >> ".$rowid : $rowid) : $binMsg;
					$binMsg = ($binid!='') ? ($binMsg!='' ? $binMsg ." >> ".$binid : $binid) : $binMsg;
					$binMsg = ($binMsg!='') ? $binMsg." of " : $binMsg;

					if(isset($this->_binTrackingDetails[$itemid][$aislerowbinkey])){
						$orgWareHouse = $this->_binTrackingDetails[$itemid][$aislerowbinkey]['WHSEKEY'];

						if(isset($this->_binTrackingDetails[$itemid][$aislerowbinkey]['TOTAL_CHILD_QTY' ])){
							$childQuantity = $this->_binTrackingDetails[$itemid][$aislerowbinkey]['TOTAL_CHILD_QTY' ];
                            /** @noinspection PhpUndefinedVariableInspection */
                            $totalChildQuantity = ibcadd($totalChildQuantity, $childQuantity, 0, false);

							if($track['QUANTITY'] < $childQuantity){
								$msg = "There are documents which consumed $childQuantity quantity from $binMsg warehouse $whsekey. Please ensure that the quantity entered is more than the consumed quantity for Item '".$itemid."' in Line# ".($track['ITEMLINENO']+1);
								$gErr->addIAError(
								    'INV-1067', __FILE__ . ':' . __LINE__,
								    $msg, ['CHILD_QUANTITY' => $childQuantity, 'BIN_MSG' => $binMsg, 'WHSEKEY' => $whsekey, 'ITEMID' => $itemid, 'TRACK_ITEMLINENO' => ($track['ITEMLINENO']+1)]
								);
								$ok=false;
							}
						}
					}
				}

				// if the quantity is consumed and the ware house is changed
                /** @noinspection PhpUndefinedVariableInspection */
                if( $ok && $totalChildQuantity > 0){
					$newWhsekey		= $whsekey;
                    /** @noinspection PhpUndefinedVariableInspection */
                    if( $newWhsekey != $orgWareHouse ){
                        /** @noinspection PhpUndefinedVariableInspection */
                        $msg = "There are documents which consumed $totalChildQuantity quantity from $binMsg warehouse $orgWareHouse for Item '" . $itemid . "' in Line# " . ( $track['ITEMLINENO'] + 1);
						$gErr->addIAError(
						    'INV-1068', __FILE__ . ':' . __LINE__,
						    "Changing Warehouse from '" . $orgWareHouse . "' to '" . $newWhsekey . "' is not allowed", ['ORG_WARE_HOUSE' => $orgWareHouse, 'NEW_WHSEKEY' => $newWhsekey],
						    $msg, ['TOTAL_CHILD_QUANTITY' => $totalChildQuantity, 'BIN_MSG' => $binMsg, 'ORG_WARE_HOUSE' => $orgWareHouse, 'ITEMID' => $itemid, 'TRACK_ITEMLINENO' => ($track['ITEMLINENO'] + 1)]
						);
						$ok=false;
					}
				}
			}
		}

		return $ok;
	}

    /**
     * @param array $values
     * @param array $entry
     * @param array $trackingInfo
     *
     * @return bool
     */
    function ValidateBinTracking_BuildKits(&$values, $entry, &$trackingInfo){
		$gManagerFactory = Globals::$g->gManagerFactory;
		$gErr = Globals::$g->gErr;

		$ok = true;
		$trackParams = $this->_trackParams;
		$docDate	= $values['WHENCREATED'];
		$recalledID		= $entry['SOURCE_DOCID'];
		$docentrycostMgr = $gManagerFactory->getManager('documententrycost');
        $newtrackinfo = [];

        $parentInfo = [];
        if (isset($entry['SOURCE_DOCKEY']) && $entry['SOURCE_DOCKEY'] != '') {
            $parentInfo = $trackParams['PARENTINFO'][$entry['SOURCE_DOCKEY']];
        }

        $advBins = BinManager::areAdvanedBinsOn();
		if ($this->_action==CREATE_ACTION || $this->_action == EDIT_ACTION) {
			$cny = GetMyCompany();
			$itemlineno = $entry['LINENO'];
			$whsekey = $entry['WAREHOUSE']['LOCATION_NO'];

            //Check each component to see if it's using an expired expiration date, by comparing with the docdate.
            foreach($trackingInfo as $track) {
                if ($track['EXPIRATION']) {
                    if ( StkitDocumentManager::isStockableKitComponentTrackingEnabled() && empty($track['COMPONENTID']) ) {
                        // The Stockable Kits are springing into existence--no quantity checks for those
                        continue;
                    }
                    $dateDiff = DateCompare($track['EXPIRATION'], $docDate);
                    if ($dateDiff === -1) {
                        $msg1 = "Unable to build kit";
                        $msgLineNo = $itemlineno + 1;
                        $msg2 = "The expiration date that is selected for component {$track['ITEMID']}  on line {$msgLineNo} for stockable kit {$entry['ITEMID']} is expired. Select an expiration date that is the same as or later than the transaction date.";
                        $gErr->addIAError(
                            'INV-1075', __FILE__ . ':' . __LINE__,
                            $msg1, [],
                            $msg2, ['TRACK_ITEMID' => $track['ITEMID'], 'MSG_LINE_NO' => $msgLineNo, 'ENTRY_ITEMID' => $entry['ITEMID']]
                        );
                        $ok = false;
                        continue; //This component has an error, go to next component or bail?
                    }
                }
            }

			if ($ok) {
                foreach ( $trackingInfo as $key => $track ) {
                    if ( StkitDocumentManager::isStockableKitComponentTrackingEnabled() && empty($track['COMPONENTID']) ) {
                        // The Stockable Kits are springing into existence--no quantity checks for those
                        continue;
                    }
                    $itemid = $track['ITEMID'];

                    $aislekey = $track['AISLEKEY'];
                    $rowkey = $track['ROWKEY'];
                    $binkey = $track['BINKEY'];

                    //If this tracking component has an expiration date, we need to use it to look up qty available
                    $expirationDate = $docDate;
                    if ($track['EXPIRATION']) {
                        $expirationDate = $track['EXPIRATION'];
                    }

				if($recalledID!='') {
                    $id = '';
                    if (!empty($parentInfo) && $parentInfo['AFFECTS_ONHAND_QTY']) {
                        $id = $recalledID;
                    } else {
                        // If the parent is affecting ONHAND quantity
                        // get the bin quantity from parent
                        // else look for available bin quantity in the warehouse
                        $sourceDocIDWithTrackingInfo = $this->getParentWithSerial($entry['SOURCE_DOCLINEKEY']);

                            if ( $sourceDocIDWithTrackingInfo != '' ) {
                                $id = $sourceDocIDWithTrackingInfo;
                            }
                        }
                        if ( $id != '' ) {
                            if ( $advBins && $binkey ) {
                                $qryGetAvailBin = 'QRY_DOCUMENTENTRYCOST_SELECT_PARENT_BINQTY_ADV';
                                $argsGetAvailBin = [ $itemid, $whsekey, $binkey, $expirationDate, $cny, $id ];
                            } else if ( $aislekey && $rowkey && $binkey ) {
                                $qryGetAvailBin = 'QRY_DOCUMENTENTRYCOST_SELECT_PARENT_BINQTY';
                                $argsGetAvailBin =
                                    [ $itemid, $whsekey, $aislekey, $rowkey, $binkey, $expirationDate, $cny, $id ];
                            } else {
                                $qryGetAvailBin = $advBins ? 'QRY_DOCUMENTENTRYCOST_SELECT_PARENT_QTY_ADV'
                                    : 'QRY_DOCUMENTENTRYCOST_SELECT_PARENT_QTY';
                                $argsGetAvailBin = [ $itemid, $whsekey, $expirationDate, $cny, $id ];
                            }
                        } else {
                            if ( ( $advBins && $binkey ) || ( $aislekey && $rowkey && $binkey ) ) {
                                if ( $advBins ) {
                                    $qryGetAvailBin = 'QRY_DOCUMENTENTRYCOST_SELECT_AVAIL_BINQTY_ADV';
                                    $argsGetAvailBin = [ $itemid, $whsekey, $binkey, $expirationDate, $cny ];
                                } else {
                                    $qryGetAvailBin = 'QRY_DOCUMENTENTRYCOST_SELECT_AVAIL_BINQTY';
                                    $argsGetAvailBin =
                                        [ $itemid, $whsekey, $aislekey, $rowkey, $binkey, $expirationDate, $cny ];
                                }
                            } else {
                                $qryGetAvailBin = $advBins ? 'QRY_DOCUMENTENTRYCOST_SELECT_AVAIL_QTY_ADV'
                                    : 'QRY_DOCUMENTENTRYCOST_SELECT_AVAIL_QTY';
                                $argsGetAvailBin = [ $itemid, $whsekey, $expirationDate, $cny, ];
                            }
                        }
                    } else {
                        if ( ( $advBins && $binkey ) || ( $aislekey && $rowkey && $binkey ) ) {
                            if ( $advBins ) {
                                $qryGetAvailBin = 'QRY_DOCUMENTENTRYCOST_SELECT_AVAIL_BINQTY_ADV';
                                $argsGetAvailBin = [ $itemid, $whsekey, $binkey, $expirationDate, $cny ];
                            } else {
                                $qryGetAvailBin = 'QRY_DOCUMENTENTRYCOST_SELECT_AVAIL_BINQTY';
                                $argsGetAvailBin = [ $itemid, $whsekey, $aislekey, $rowkey, $binkey, $expirationDate, $cny ];
                            }
                        } else {
                            $qryGetAvailBin = $advBins ? 'QRY_DOCUMENTENTRYCOST_SELECT_AVAIL_QTY_ADV'
                                : 'QRY_DOCUMENTENTRYCOST_SELECT_AVAIL_QTY';
                            $argsGetAvailBin = [ $itemid, $whsekey, $expirationDate, $cny, ];
                        }
                    }

                    $rows = $docentrycostMgr->DoQuery($qryGetAvailBin, $argsGetAvailBin);

                    //If we have an expriation date, we should only have 1 row to validate QTYLEFT, so get that one.
                    if ($track['EXPIRATION']) {
                        $rowWithExpirationDate = null;
                        foreach ( $rows as $row ) {
                            $dateDiff = DateCompare($track['EXPIRATION'], $row['EXPIRATION']);
                            if ($dateDiff === 0) {
                                $rowWithExpirationDate[] = $row;
                            }
                        }
                        $rows = $rowWithExpirationDate;
                    }

                    if ( $rows ) {
                        $total_qtyleft = 0;
                        foreach ( $rows as $row ) {
                            $total_qtyleft += $row['QTYLEFT'];
                        }

                        if ( $track['QUANTITY'] > $total_qtyleft ) {
                            //Insufficient qty left
                            $msg1 = "Unable to build kit";
                            $msgLineNo = $itemlineno + 1;
                            $msg2 = "There's not enough quantity specified for component {$track['ITEMID']} on line {$msgLineNo} for stockable kit {$entry['ITEMID']}. Check for quantity using other lot, serial, or bin combinations.";
                            $gErr->addIAError(
                                'INV-1076', __FILE__ . ':' . __LINE__,
                                $msg1, [],
                                $msg2, ['TRACK_ITEMID' => $track['ITEMID'], 'MSG_LINE_NO' => $msgLineNo, 'ENTRY_ITEMID' => $entry['ITEMID']]
                            );
                            $ok = false;
                        } else {
                            $totalqtyrequired = $track['QUANTITY'];

                            // we need to split the trackinginfo into several lines
                            foreach ( $rows as $row ) {
                                if ( $totalqtyrequired > 0 ) {
                                    //Check to see if we have qty to use else skip the row
                                    if ( $row['QTYLEFT'] <= 0 ) {
                                        continue;
                                    }

                                    $track['QUANTITY'] = min($row['QTYLEFT'], $totalqtyrequired);
                                    $totalqtyrequired -= $track['QUANTITY'];

                                    // reduce the quantity left of the source
                                    // row qtyleft=qty available, track qty=qty consumed from this doc
                                    // so qty left in this doc=row qty left - track qty
                                    if ( ! $aislekey && ! $rowkey && ! $binkey ) {
                                        $track['AISLEKEY'] = $row['AISLEID'];
                                        $track['ROWKEY'] = $row['ROWID'];
                                        $track['BINKEY'] = $row['BINID'];
                                    }
                                    $newtrackinfo[$key][] = $track;
                                } else {
                                    break;
                                }
                            }
                        }
                    } else {
                        $binMsg = ( $binMsg != '' ) ? $binMsg . " of " : $binMsg;
                        //No qty left
                        $msg1 = "Unable to build kit";
                        $msgLineNo = $itemlineno + 1;
                        $msg2 = "There's not enough quantity specified for component {$track['ITEMID']} on line {$msgLineNo} for stockable kit {$entry['ITEMID']}. Check for quantity using other lot, serial, or bin combinations.";
                        $gErr->addIAError(
                            'INV-1000', __FILE__ . ':' . __LINE__,
                            $msg1, [],
                            $msg2, ['TRACK_ITEMID' => $track['ITEMID'], 'MSG_LINE_NO' => $msgLineNo, 'ENTRY_ITEMID' => $entry['ITEMID']]
                        );
                        $ok = false;
                    }
                }

                // merge all the splited lines
                if ( ( ! empty($newtrackinfo) ) ) {
                    $temptrackingInfo = $trackingInfo;
                    $trackingInfo = [];
                    foreach ( $temptrackingInfo as $key => $track ) {
                        if ( isset($newtrackinfo[$key]) ) {
                            foreach ( $newtrackinfo[$key] as $newinfo ) {
                                $trackingInfo[] = $newinfo;
                            }
                        } else {
                            $trackingInfo[] = $temptrackingInfo[$key];
                        }
                    }
                }
            }
        }

		return $ok;
	}

    /**
     * @param array $values
     * @param array $entry
     * @param array $trackingInfo
     *
     * @return bool
     */
    function ValidateBinTracking_Sales_PurchaseReturn(
        /** @noinspection PhpUnusedParameterInspection */ &$values, $entry, &$trackingInfo) {
		$gManagerFactory = Globals::$g->gManagerFactory;
		$gErr = Globals::$g->gErr;

		$ok = true;
		$trackParams = $this->_trackParams;
		$cny = GetMyCompany();
		$itemlineno = $entry['LINENO'];
		$whsekey = $entry['WAREHOUSE']['LOCATION_NO'];
		$docDate	= $trackParams['DOCDATE'];
		$recalledID		= $entry['SOURCE_DOCID'];
		$docentrycostMgr = $gManagerFactory->getManager('documententrycost');

        $parentInfo = [];
        if (isset($entry['SOURCE_DOCKEY']) && $entry['SOURCE_DOCKEY'] != '') {
            $parentInfo = $trackParams['PARENTINFO'][$entry['SOURCE_DOCKEY']];
        }

		if(isset($trackingInfo)){
			$itemid = $trackingInfo[0]['ITEMID'];
		}else{
			$itemid		= $entry['ITEMID'];
		}
        $advBins = BinManager::areAdvanedBinsOn();

        foreach( $trackingInfo as $track){
			$aislekey = $track['AISLEKEY'];
			$rowkey = $track['ROWKEY'];
			$binkey = $track['BINKEY'];

			$aisleid = $track['AISLEID'];
			$rowid = $track['ROWID'];
			$binid = $track['BINID'];

			$binMsg = $aisleid;
			$binMsg = ($rowid!='') ? ($binMsg!='' ? $binMsg ." >> ".$rowid : $rowid) : $binMsg;
			$binMsg = ($binid!='') ? ($binMsg!='' ? $binMsg ." >> ".$binid : $binid) : $binMsg;

			if($this->_action==CREATE_ACTION || $this->_action == EDIT_ACTION){
				if($recalledID!=''){
					$qryGetAvailBin = 'QRY_DOCUMENTENTRYCOST_SELECT_PARENT_BINQTY';
                    if (!empty($parentInfo) && $parentInfo['AFFECTS_ONHAND_QTY']) {
						$argsGetAvailBin	= array($itemid, $whsekey, $aislekey, $rowkey, $binkey, $docDate,$cny,$recalledID);
					}else{
						// If the parent is affecting ONHAND quantity
						// get the bin quantity from parent
						// else look for available bin quantity in the warehouse
                        $sourceDocIDWithTrackingInfo = $this->getParentWithSerial($entry['SOURCE_DOCLINEKEY']);
                        if ($sourceDocIDWithTrackingInfo != '') {
                            $argsGetAvailBin	= array($itemid, $whsekey, $aislekey, $rowkey, $binkey, $docDate,$cny,$sourceDocIDWithTrackingInfo);
						}else{
                            if ($advBins) {
                                $qryGetAvailBin =  'QRY_DOCUMENTENTRYCOST_SELECT_AVAIL_BINQTY_ADV';
                                $argsGetAvailBin = array($itemid, $whsekey, $binkey, $docDate, $cny);
                            } else {
                                $qryGetAvailBin =  'QRY_DOCUMENTENTRYCOST_SELECT_AVAIL_BINQTY';
                                $argsGetAvailBin = array($itemid, $whsekey, $aislekey, $rowkey, $binkey, $docDate, $cny);
                            }
                        }
					}
				}else{
				    if ($binid == self::TRACK_EMPTY_FIELD) {
                        $qryGetAvailBin =  'QRY_DOCUMENTENTRYCOST_SELECT_AVAIL_BINQTY_EMPTY';   // from Warehouse Transfer
                        $argsGetAvailBin = array($cny, $itemid, $whsekey);
                    } else {
                        if ($advBins) {
                            $qryGetAvailBin = 'QRY_DOCUMENTENTRYCOST_SELECT_AVAIL_BINQTY_ADV';
                            $argsGetAvailBin = array($itemid, $whsekey, $binkey, $docDate, $cny);
                        } else {
                            $qryGetAvailBin = 'QRY_DOCUMENTENTRYCOST_SELECT_AVAIL_BINQTY';
                            $argsGetAvailBin = array($itemid, $whsekey, $aislekey, $rowkey, $binkey, $docDate, $cny);
                        }
                    }
				}
			}

            /** @noinspection PhpUndefinedVariableInspection */
            $rows = $docentrycostMgr->DoQuery($qryGetAvailBin, $argsGetAvailBin);

            // Now, if this is an UPDATE of a record, add in the stuff the current record is using.....
            $recno = $entry['RECORDNO'] ?? 0; // 0 means it is a new record
            if (($recno > 0) && isset($values['EXISTING_ENTRIES'][$recno]['EXISTING_TRACKINGENTRIES'])) {
                $existingTracking =   $values['EXISTING_ENTRIES'][$recno]['EXISTING_TRACKINGENTRIES'];
                foreach ($existingTracking as $exTrackingRow) {
                    $rows[] = ['QTYLEFT' => $exTrackingRow['QUANTITY']]; // don't even really need this.....
                }
            }

			if (empty($rows)) {
			    $errorCode = 'INV-1069';
			    $placeholder = ['WHSEKEY' => $whsekey, 'ITEMID' => $itemid, 'ITEMLINENO' => ($itemlineno+1)];
				if($binMsg!=''){
				    $binMsg = $binMsg." of ";
				    $errorCode = 'INV-1074';
				    $placeholder = array_merge($placeholder, ['BIN_MSG' => $binMsg]);
				}
				// error no quantity available for this bin
				$msg = $binMsg." warehouse ".$whsekey." has no quantity. Please select Aisle/Row/Bin with sufficient quantity for Item '".$itemid."' in Line# ".($itemlineno+1);
				$gErr->addIAError($errorCode, __FILE__ . ':' . __LINE__, $msg, $placeholder);
				$ok = false;
			}
		}

//		// merge all the splited lines
//        /** @noinspection PhpUndefinedVariableInspection */
//        if( count($newtrackinfo) > 0 ){
//			$temptrackingInfo = $trackingInfo;
//			$trackingInfo = [];
//            foreach( $temptrackingInfo as $key => $track){
//				if(isset($newtrackinfo[$key])){
//					foreach($newtrackinfo[$key] as $newinfo){
//						$trackingInfo[] = $newinfo;
//					}
//				}else{
//					$trackingInfo[] = $temptrackingInfo[$key];
//				}
//			}
//		}

		return $ok;
	}

    /**
     * @param array $values
     * @param array $entry
     * @param array $trackingInfo
     *
     * @return bool
     */
    function ValidateBinTracking_SalesReturn(
        /** @noinspection PhpUnusedParameterInspection */ &$values, $entry, &$trackingInfo) {
		$gManagerFactory = Globals::$g->gManagerFactory;
		$gErr = Globals::$g->gErr;

		$ok = true;
		$trackParams = $this->_trackParams;
		$cny = GetMyCompany();
		$itemlineno = $entry['LINENO'];
		$whsekey = $entry['WAREHOUSE']['LOCATION_NO'];
		$docentrycostMgr = $gManagerFactory->getManager('documententrycost');

        $parentInfo = [];
        if (isset($entry['SOURCE_DOCKEY']) && $entry['SOURCE_DOCKEY'] != '') {
            $parentInfo = $trackParams['PARENTINFO'][$entry['SOURCE_DOCKEY']];
        }

		if(isset($trackingInfo)){
			$itemid = $trackingInfo[0]['ITEMID'];
		}else{
			$itemid		= $entry['ITEMID'];
		}

		//$recalledID = $values['CREATEDFROM'];
		$recalledID		= $entry['SOURCE_DOCID'];
		$advBns         = BinManager::areAdvanedBinsOn();

        foreach( $trackingInfo as $track){
			// --- ### need to remove the following look like not used
			//$aislekey = $track['AISLEKEY'];
			//$rowkey = $track['ROWKEY'];
			//$binkey = $track['BINKEY'];

			$aisleid = $track['AISLEID'];
			$rowid = $track['ROWID'];
			$binid = $track['BINID'];

			$binMsg = $aisleid;
			$binMsg = ($rowid!='') ? ($binMsg!='' ? $binMsg ." >> ".$rowid : $rowid) : $binMsg;
			$binMsg = ($binid!='') ? ($binMsg!='' ? $binMsg ." >> ".$binid : $binid) : $binMsg;

			if ($recalledID!=''){
				$qryGetAvailBin = $advBns ? 'QRY_DOCUMENTENTRYCOST_SELECT_PARENT_BIN_SALERETURN_ADV' : 'QRY_DOCUMENTENTRYCOST_SELECT_PARENT_BIN_SALERETURN';
                if (!empty($parentInfo) && $parentInfo['AFFECTS_ONHAND_QTY']) {
					$argsGetAvailBin	= array($itemid, $recalledID, $cny);
				}else{
                    $sourceDocIDWithTrackingInfo = $this->getParentWithSerial($entry['SOURCE_DOCLINEKEY']);
                    $argsGetAvailBin = array($itemid, $sourceDocIDWithTrackingInfo, $cny);
				}

				$rows = $docentrycostMgr->DoQuery($qryGetAvailBin,$argsGetAvailBin);
			}else{
				$qry = $advBns ? 'QRY_DOCUMENTENTRYCOST_SELECT_AVAIL_BIN_SALESRETURN_ADV' : 'QRY_DOCUMENTENTRYCOST_SELECT_AVAIL_BIN_SALESRETURN';
				$args = array($itemid,$cny,);
				$rows = $docentrycostMgr->DoQuery($qry,$args);
			}

            // Now, if this is an UPDATE of a record, add in the stuff the current record is using.....
            $recno = $entry['RECORDNO'] ?? 0; // 0 means it is a new record
            if (($recno > 0) && isset($values['EXISTING_ENTRIES'][$recno]['EXISTING_TRACKINGENTRIES'])) {
                $existingTracking =   $values['EXISTING_ENTRIES'][$recno]['EXISTING_TRACKINGENTRIES'];
                foreach ($existingTracking as $exTrackingRow) {
                    $rows[] = ['QTYLEFT' => $exTrackingRow['QUANTITY']]; // don't even really need this.....
                }
            }

            if (empty($rows)) {
				$errorCode = 'INV-1006';
                $placeholder = ['WHSEKEY' => $whsekey, 'ITEMID' => $itemid, 'ITEMLINENO' => ($itemlineno+1)];
                if($binMsg!=''){
                    $binMsg = $binMsg." of ";
                    $errorCode = 'INV-1007';
                    $placeholder = array_merge($placeholder, ['BIN_MSG' => $binMsg]);
                }
				// error no quantity available for this bin
				$msg = $binMsg." warehouse ".$whsekey." has no quantity. Please select Aisle/Row/Bin with sufficient quantity for Item '".$itemid."' in Line# ".($itemlineno+1);
				$gErr->addIAError($errorCode, __FILE__ . ':' . __LINE__, $msg, $placeholder);
				$ok = false;
			}
		} // end of for

		// merge all the splited lines
//        /** @noinspection PhpUndefinedVariableInspection */
//        if( count($newtrackinfo) > 0 ){
//			$temptrackingInfo = $trackingInfo;
//			$trackingInfo = [];
//            foreach( $temptrackingInfo as $key => $track){
//				if(isset($newtrackinfo[$key])){
//					foreach($newtrackinfo[$key] as $newinfo){
//						$trackingInfo[] = $newinfo;
//					}
//				}else{
//					$trackingInfo[] = $temptrackingInfo[$key];
//				}
//			}
//		}

		return $ok;
	}

	// most of the code is cleaned.
    /**
     * @param int $dochdrkey
     */
    function PrepParentChildBinTrackingDetailsMap($dochdrkey){
		$this->_binTrackingDetails = [];
		$cny = GetMyCompany();

		// get the docentrycost entries for current document
		$queryParentDetails = "SELECT docentrycost.*, icaisle.aisleid, icrow.rowkey row_id, icbin.binid, docentry.lineno itemlineno
						FROM docentrycost
						  INNER JOIN docentry ON docentry.cny# = docentrycost.cny# AND docentry.record# = docentrycost.docentrykey
						  INNER JOIN icitem ON icitem.cny# = docentrycost.cny# AND icitem.itemid = docentrycost.itemkey 
						              AND icitem.enablebin = 'T' AND nvl(icitem.enablesno,'F') = 'F' AND nvl(icitem.enablelot,'F') = 'F'
						  LEFT OUTER JOIN icaisle ON icaisle.cny# = docentrycost.cny# AND icaisle.record# = docentrycost.aislekey
						  LEFT OUTER JOIN icrow ON icrow.cny# = docentrycost.cny# AND icrow.record# = docentrycost.rowkey
						  LEFT OUTER JOIN icbin ON icbin.cny# = docentrycost.cny# AND icbin.record# = docentrycost.binkey
						WHERE docentrycost.cny# = :1
						  AND docentrycost.affects_inventory IN ('Q','QV')
						  AND docentry.dochdrkey = :2
						ORDER BY docentrycost.itemkey, docentrycost.aislekey, docentrycost.binkey, docentrycost.rowkey ";

		$parentDetails = QueryResult(array($queryParentDetails,$cny, $dochdrkey));
		// resting the ROW_ID to ROWID. ROWID in the query is not allowed by oracle
		changeKeyName($parentDetails, 'ROWID', 'ROW_ID');

		$queryChildDetails = "SELECT docentrycost.*, icaisle.aisleid, icrow.rowkey row_id, icbin.binid
						FROM docentrycost
						LEFT OUTER JOIN icaisle ON icaisle.cny# = :1 AND icaisle.record# = docentrycost.aislekey
						LEFT OUTER JOIN icrow ON icrow.cny# = :1 AND icrow.record# = docentrycost.rowkey
						LEFT OUTER JOIN icbin ON icbin.cny# = :1 AND icbin.record# = docentrycost.binkey
						WHERE docentrycost.cny#          = :1 
						AND docentrycost.affects_inventory IN ('Q','QV')
						AND docentrycost.docentrycostkey = :2
						ORDER BY docentrycost.itemkey, docentrycost.aislekey, docentrycost.binkey, docentrycost.rowkey";

        foreach ($parentDetails as $pKey => $pEntry) {
			$pEntry = $parentDetails[$pKey];
			$parentkey = $pEntry['ITEMLINENO']."|".$pEntry['AISLEID']."|".$pEntry['ROWID']."|".$pEntry['BINID']."|".$pEntry['EXPIRATIONDATE'];
			$totalChildQty=0;
			$childDetails = QueryResult(array($queryChildDetails,$cny, $pEntry['RECORD#']));
			// resting the ROW_ID to ROWID. ROWID in the query is not allowed by oracle
			changeKeyName($childDetails, 'ROWID', 'ROW_ID');

            foreach ($childDetails as $cEntry) {
				$totalChildQty = ibcadd($totalChildQty, $cEntry['QUANTITY'],0,true);
				$pEntry['CHILD_DETAILS'][] = $cEntry;
			}

			$pEntry['TOTAL_CHILD_QTY'] = $totalChildQty;
			$this->_binTrackingDetails[$pEntry['ITEMKEY']][$parentkey] = $pEntry;
		}
	}
	//
	// most of the code is cleaned.
    /**
     * @param int $dochdrkey
     */
    function PrepParentChildSerialTrackingDetailsMap($dochdrkey){
		// --- ### --- this function is called from DocumentManager::Set -> DocumentManager::DeleteOldValuesForUpdate
		$this->_serialTrackingDetails = [];
		$cny = GetMyCompany();

		// select only the SerialNo enabled item entries
		// from the docentrycost for current document
		$queryParentDetails = "SELECT docentrycost.*, icaisle.aisleid, icrow.rowkey row_id, icbin.binid, docentry.lineno itemlineno
					FROM docentrycost
					LEFT OUTER JOIN docentry ON docentry.cny# = :1 AND docentry.record# = docentrycost.docentrykey
					LEFT OUTER JOIN icaisle ON icaisle.cny# = :1 AND icaisle.record# = docentrycost.aislekey
					LEFT OUTER JOIN icrow ON icrow.cny# = :1 AND icrow.record# = docentrycost.rowkey
					LEFT OUTER JOIN icbin ON icbin.cny# = :1 AND icbin.record# = docentrycost.binkey
					LEFT OUTER JOIN icitem ON icitem.cny# = :1 AND icitem.itemid = docentrycost.itemkey AND icitem.enablesno = 'T'
					WHERE docentrycost.cny# = :1
					AND docentrycost.affects_inventory IN ('Q','QV')
					AND docentrycost.serialno          IS NOT NULL
					AND docentry.dochdrkey              = :2
					ORDER BY docentrycost.itemkey, docentrycost.serialno";

		$parentDetails = QueryResult(array($queryParentDetails,$cny, $dochdrkey));

		// resting the ROW_ID to ROWID
		// ROWID in the query is not allowed by oracle
		changeKeyName($parentDetails, 'ROWID', 'ROW_ID');

		$queryChildDetails = "SELECT docentrycost.*, icaisle.aisleid, icrow.rowkey row_id, icbin.binid
						FROM docentrycost
						LEFT OUTER JOIN icaisle ON icaisle.cny# = :1 AND icaisle.record# = docentrycost.aislekey
						LEFT OUTER JOIN icrow ON icrow.cny# = :1 AND icrow.record# = docentrycost.rowkey
						LEFT OUTER JOIN icbin ON icbin.cny# = :1 AND icbin.record# = docentrycost.binkey
						WHERE docentrycost.cny#          = :1 
						AND docentrycost.affects_inventory IN ('Q','QV')
						AND docentrycost.serialno         IS NOT NULL
						AND docentrycost.docentrycostkey = :2
						AND docentrycost.itemkey         = :3
						ORDER BY docentrycost.itemkey, docentrycost.serialno";


		// get the child entries for each parent entry
        foreach( $parentDetails as $pEntry){
			$childDetails = QueryResult(array($queryChildDetails,$cny, $pEntry['RECORD#'], $pEntry['ITEMKEY']));
			// resting the ROW_ID to ROWID
			// ROWID in the query is not allowed by oracle
			changeKeyName($childDetails, 'ROWID', 'ROW_ID');

			if(count($childDetails) > 1){
				// this should not be the case ;
				// serial number should be one to one (one parent - one child)
				// --- ### throw error instead
				dieFL('--- multiple child entries found for same serial number ---');
			}else{
				$pEntry['CHILD_DETAILS'] = $childDetails[0];
			}

			$this->_serialTrackingDetails[$pEntry['ITEMKEY']][$pEntry['SERIALNO']] = $pEntry;
		}
	}

	//most of the code is cleaned.

    /**
     * @param int $dochdrkey
     */
    function PrepParentChildLotTrackingDetailsMap($dochdrkey){
		$this->_lotTrackingDetails = [];
		$cny = GetMyCompany();

		// select only the bin enabled item entries
		// get the docentrycost entries for current document
		$queryParentDetails ="SELECT docentrycost.*, icaisle.aisleid, icrow.rowkey row_id, icbin.binid, docentry.lineno itemlineno
					FROM docentrycost
					LEFT OUTER JOIN docentry ON docentry.cny# = :1 AND docentry.record# = docentrycost.docentrykey
					LEFT OUTER JOIN icaisle ON icaisle.cny# = :1 AND icaisle.record# = docentrycost.aislekey
					LEFT OUTER JOIN icrow ON icrow.cny# = :1 AND icrow.record# = docentrycost.rowkey
					LEFT OUTER JOIN icbin ON icbin.cny# = :1 AND icbin.record# = docentrycost.binkey
					LEFT OUTER JOIN icitem ON icitem.cny# = :1 AND icitem.itemid = docentrycost.itemkey AND icitem.enablelot = 'T'
					WHERE docentrycost.cny# = :1
					AND docentrycost.affects_inventory IN ('Q','QV')
					AND docentrycost.lotno          IS NOT NULL
					AND docentry.dochdrkey              = :2
					ORDER BY docentrycost.itemkey, docentrycost.lotno";

		$parentDetails = QueryResult(array($queryParentDetails,$cny, $dochdrkey));

		// resting the ROW_ID to ROWID
		// ROWID in the query is not allowed by oracle
		changeKeyName($parentDetails, 'ROWID', 'ROW_ID');

		// get the child entries for each parent entry
        foreach( $parentDetails as $pEntry){
			$queryChildDetails = "SELECT docentrycost.*, icaisle.aisleid, icrow.rowkey row_id, icbin.binid
						FROM docentrycost
						LEFT OUTER JOIN icaisle ON icaisle.cny# = :1 AND icaisle.record# = docentrycost.aislekey
						LEFT OUTER JOIN icrow ON icrow.cny# = :1 AND icrow.record# = docentrycost.rowkey
						LEFT OUTER JOIN icbin ON icbin.cny# = :1 AND icbin.record# = docentrycost.binkey
						WHERE docentrycost.cny#          = :1 
						AND docentrycost.affects_inventory IN ('Q','QV')
						AND docentrycost.lotno         IS NOT NULL
						AND docentrycost.docentrycostkey = :2
						AND docentrycost.itemkey         = :3
						ORDER BY docentrycost.itemkey, docentrycost.lotno";

			$childDetails = QueryResult(array($queryChildDetails,$cny, $pEntry['RECORD#'], $pEntry['ITEMKEY']));
			// resting the ROW_ID to ROWID
			// ROWID in the query is not allowed by oracle
			changeKeyName($childDetails, 'ROWID', 'ROW_ID');

			$pEntry['CHILD_DETAILS'] = $childDetails;
			$this->_lotTrackingDetails[$pEntry['ITEMKEY']][$pEntry['LOTNO']] = $pEntry;
		}
	}





	// this may not be required as we have a warehouse cache which has this information
	//
	// --- ### this function may not be required as we can get the same info from $_whaeARBcache
	// function GetDefaultAisleRowBinInfo()
    /**
     * @param int    $cny
     * @param string $itemid
     * @param string $whse
     *
     * @return array
     */
    function GetDefaultAisleRowBinInfo($cny, $itemid, $whse) {

        $arbInfo = [];
		global $gManagerFactory;

		$itemWhseMgr		= $gManagerFactory->getManager('itemwarehouseinfo');

		// For stockable kits where bin tracking is enabled, get default aisle/row/bin from icitemwhse
		$qry = 'QRY_ITEMWAREHOUSEINFO_SELECT_BY_ITEM_WHSE';
		$args = array($cny,$itemid,$whse);
		$res= $itemWhseMgr->DoQuery($qry,$args);
		if (is_array($res) && !empty($res)) {
		    $arbInfo=array(0=>array('ITEMID'=>$itemid,
                                    'AISLEKEY'=>$res[0]['AISLEKEY'],
                                    'ROWKEY'=>$res[0]['ROWKEY'],
                                    'BINKEY'=>$res[0]['BINKEY'],
                                    'AISLEID'=>$res[0]['AISLEID'],
                                    'ROWID'=>$res[0]['ROWID'],
                                    'BINID'=>$res[0]['BINID']));
        }
		return $arbInfo;

	}


	// ---### this may not be required as per discussion with PM

    /**
     * @param array $values
     */
    function ConsolidateLotTrackingValues(&$values)
	{
		$consvalues = array();

		foreach($values[''] as $val){
			if (hasValue($val['LOTNO'])) {
				$lotexpaislerowbinkey = $val['LOTNO']."|".$val['EXPIRATION']."|".$val['AISLEKEY']."|".$val['ROWKEY']."|".$val['BINKEY'];
				$consvalues[$lotexpaislerowbinkey]['QUANTITY'] = ibcadd($consvalues[$lotexpaislerowbinkey]['QUANTITY'], $val['QUANTITY'], DEFAULT_INVPRECISION, true);
				$consvalues[$lotexpaislerowbinkey]['REC'] = $val;
			}
		}

        foreach( $consvalues as $val){
			$val['REC']['QUANTITY'] = $val['QUANTITY'];
			$tempconsvalues[] = $val['REC'];
		}
        /** @noinspection PhpUndefinedVariableInspection */
        $values['']=$tempconsvalues;
	}

	//---### this may not be required as per discussion with PM

    /**
     * @param array $values
     */
    function ConsolidateBinTrackingValues(&$values)
	{
        $consvalues     = [];
        $tempconsvalues = [];

        foreach($values[''] as $val){
            $aislerowbinkey = ($val['AISLEKEY'] ?? '') ."|". ($val['ROWKEY'] ?? '') ."|". ($val['BINKEY'] ?? '') ."|". ($val['EXPIRATION'] ?? '');
            $consvalues[$aislerowbinkey]['QUANTITY'] = ibcadd($consvalues[$aislerowbinkey]['QUANTITY'] ?? 0, $val['QUANTITY'] ?? 0, 0, true);
            $consvalues[$aislerowbinkey]['REC'] = $val;
        }

        foreach( $consvalues as $val){
            $val['REC']['QUANTITY'] = $val['QUANTITY'];
            $tempconsvalues[] = $val['REC'];
        }

        $values[''] = $tempconsvalues;
	}


	// prepare aisles, rows & bins as cache
	function PrepAllWarehouseRowsCache()
	{
		$gManagerFactory = Globals::$g->gManagerFactory;
		$rowMgr = $gManagerFactory->getManager('icrow');
		$cny= GetMyCompany();

		$qry = 'QRY_ROWS_GET_IN_ALL_WHSE';
		$args = array($cny);

		$rows    = $rowMgr->DoQuery($qry, $args);
        foreach( $rows as $row){
			$this->_whaeARBcache[$row['WHSEKEY']]['ROWS'][$row['ROW_ID']] = $row;
		}
	}

	function PrepAllWarehouseAislesCache()
	{
		$gManagerFactory = Globals::$g->gManagerFactory;
		$aisleMgr = $gManagerFactory->getManager('aisle');
		$cny= GetMyCompany();

		$qry     = 'QRY_AISLES_GET_IN_ALL_WHSE';
		$args     = array ($cny);
		$aisles = $aisleMgr->DoQuery($qry, $args);

        foreach( $aisles as $aisle){
			$this->_whaeARBcache[$aisle['WHSEKEY']]['AISLES'][$aisle['AISLEID']] = $aisle;
		}
	}

	function PrepAllWarehouseBinsCache()
	{
		$gManagerFactory = Globals::$g->gManagerFactory;
		$binMgr = $gManagerFactory->getManager('bin');
		$cny= GetMyCompany();

		$qry     = (BinManager::areAdvanedBinsOn() ? 'QRY_BINS_GET_IN_ALL_WHSE_ADV' : 'QRY_BINS_GET_IN_ALL_WHSE');
		$args     = array ($cny);

		$bins = $binMgr->DoQuery($qry, $args);
        foreach( $bins as $bin){
			$this->_whaeARBcache[$bin['WHSEKEY']]['BINS'][$bin['BINID']] = $bin;
		}
	}

	function PrepSerialMaskCache(){
		$gManagerFactory = Globals::$g->gManagerFactory;
		$serialMaskMgr = $gManagerFactory->getManager('serialmask');
		$serialMasks = $serialMaskMgr->GetList();

        foreach( $serialMasks as $mask){
			$maskPattern = $this->PrepSerialMaskRegExPattern($mask['MASK']);
            $mappedSerialMasks[$mask['RECORDNO']] = array('MASK' => $mask['MASK'],
															'REG_EX_PATTERN'=>$maskPattern);
		}

        /** @noinspection PhpUndefinedVariableInspection */
        $this->_serialMaskCache = $mappedSerialMasks;
	}


    /**
     * @param string $serialMask
     *
     * @return string
     */
    function PrepSerialMaskRegExPattern($serialMask){
        $patternCap     = "[A-Z]";
        $patternLow     = "[a-z]";
        $patternDig     = "[0-9]";
        $patternAny     = ".";
        $patternSpace   = '\s';
        $pattern        = "";
        $escapeOn       = false;
        $len = isl_strlen($serialMask);
        for($i=0; $i < $len; $i++) {
            $c = $serialMask[$i];
            if  ($c == "'") {
                $escapeOn = !$escapeOn;
            } else if ($escapeOn) {
                if ((($c >= 'A') && ($c <= 'Z')) || (($c >= 'a') && ($c <= 'z')) || (($c >= '0') && ($c <= '9'))) {
                    $pattern = $pattern . $c;
                } else {
                    $pattern = $pattern . '\\' . $serialMask[$i];   // escape special chars
                }
            } else if ($c == 'A') {
                $pattern = $pattern . $patternCap;
            } else if ($c == 'a') {
                $pattern = $pattern . $patternLow;
            } else if ($c == 'N') {
                $pattern = $pattern . $patternDig;
            } else if ($c == '?') {
                $pattern = $pattern . $patternAny;
            } else if ($c == ' ') {
                $pattern = $pattern . $patternSpace;
            } else {
                // SYNTAX ERROR IN PATTERN
            }
        }
        $pattern = "/".$pattern."/";
        return $pattern;
    }


    /**
     * @param string $itemID
     * @param string $what                     
     *
     * @return bool
     */
    private function isItemEnabledForTracking($itemID, $what='')
	{
		$item = $this->_itemsRawCache[$itemID];
		
		switch ($what) {
            case SERIALNO_ENABLED:
                $enabled = ($item['ENABLESNO']=='T');
                break;
            case LOTNO_ENABLED:
                $enabled = ($item['ENABLELOT']=='T');
                break;
            case BINNO_ENABLED:
                $enabled = ($item['ENABLEBIN']=='T');
                break;
            case EXPIRATION_ENABLED:
                $enabled = ($item['ENABLEEXPIRATION']=='T');
                break;             
            default:
                $enabled = ($item['ENABLESNO']=='T' || $item['ENABLELOT']=='T' || $item['ENABLEBIN']=='T' || $item['ENABLEEXPIRATION']=='T');
        }

        return $enabled;
	}

    /**
     * @param int $dochdrkey
     *
     * @return array
     */
    function GetAvailableTrackingDetails($dochdrkey){
        $cny = GetMyCompany();

        //
        //Get parent tracking details representing docentrytrackdetail for a source document such as a sales oder
        $queryParentDetails = "SELECT det.record# recordno, det.itemkey itemid, det.docentrykey docentryno,
 										det.quantity, det.serialno, det.lotno, det.aislekey, det.rowkey, det.binkey, det.expirationdate expiration,
 									 	icaisle.aisleid, icrow.rowkey row_id, icbin.binid, 
 									 	de.lineno itemlineno, de.itemkey parent_itemid, de.warehousekey, 
 									 	icitem.enablesno, icitem.enablelot, icitem.enablebin, icitem.enableexpiration
					FROM docentrytrackdetail det
					LEFT OUTER JOIN docentry de ON de.cny# = :1 AND de.record# = det.docentrykey
					LEFT OUTER JOIN icaisle ON icaisle.cny# = :1 AND icaisle.record# = det.aislekey
					LEFT OUTER JOIN icrow ON icrow.cny# = :1 AND icrow.record# = det.rowkey
					LEFT OUTER JOIN icbin ON icbin.cny# = :1 AND icbin.record# = det.binkey
					LEFT OUTER JOIN icitem ON icitem.cny# = :1 AND icitem.itemid = det.itemkey
					AND (icitem.enablesno = 'T' or icitem.enablelot = 'T' or icitem.enablebin = 'T' or icitem.enableexpiration = 'T')
					WHERE det.cny# = :1
					--AND docentrycost.affects_inventory IN ('Q','QV')
					--AND det.serialno          IS NOT NULL 
					AND de.dochdrkey              = :2
					ORDER BY det.itemkey, det.serialno";
        $parentDetails = QueryResult(array($queryParentDetails, $cny, $dochdrkey));
        // resting the ROW_ID to ROWID
        // ROWID in the query is not allowed by oracle
        changeKeyName($parentDetails, 'ROWID', 'ROW_ID');

        //
        //Get children tracking details representing all converted to documents (partial conversion) from the source document above
        $queryChildren = "SELECT det.record# recordno, det.itemkey itemid, det.docentrykey docentryno,
 										det.quantity, det.serialno, det.lotno, det.aislekey, det.rowkey, det.binkey, det.expirationdate expiration,
 									 	icaisle.aisleid, icrow.rowkey row_id, icbin.binid, 
 									 	de.lineno itemlineno, de.itemkey parent_itemid, de.warehousekey, de.source_doclinekey source_doclinekey
						FROM docentrytrackdetail det
						LEFT OUTER JOIN docentry de ON de.cny# = :1 AND de.record# = det.docentrykey
						LEFT OUTER JOIN icaisle ON icaisle.cny# = :1 AND icaisle.record# = det.aislekey
						LEFT OUTER JOIN icrow ON icrow.cny# = :1 AND icrow.record# = det.rowkey
						LEFT OUTER JOIN icbin ON icbin.cny# = :1 AND icbin.record# = det.binkey
						WHERE det.cny# = :1
						AND de.source_dockey = :2";
        $queryChildrenDetails = QueryResult(array($queryChildren,$cny, $dochdrkey));
        // resting the ROW_ID to ROWID
        // ROWID in the query is not allowed by oracle
        changeKeyName($queryChildrenDetails, 'ROWID', 'ROW_ID');

        //Create a map of the children details above so we can look up quickly below
        $consumedDetails = [];
        foreach($queryChildrenDetails as $child) {
            $key = $child['SOURCE_DOCLINEKEY'] .$child['ITEMID'] .$child['SERIALNO'];
            $consumedDetails[$key][] = $child;
        }

        //
        //Walk through the parent track details (source document) and compare with the children track details to see
        //what parent track details have not been used and return them
        $availTrackingDetails = array();
        foreach( $parentDetails as $pEntry){

            $key = $pEntry['DOCENTRYNO'] .$pEntry['ITEMID'] .$pEntry['SERIALNO'];
            $childDetails = &$consumedDetails[$key];

            // Since we unset $childDetails elements, check if non-null before counting
            if($pEntry['ENABLESNO'] == 'T' && count($childDetails ?? []) > 1){
                // this should not be the case ;
                // serial number should be one to one (one parent - one child)
                // --- ### throw error instead
                dieFL('--- multiple child entries found for same serial number ---');
            }

            $isFullyConsumed = false;
            foreach( $childDetails as $index => $cEntry){
                if($pEntry['ENABLESNO'] == 'T' && $pEntry['SERIALNO'] == $cEntry['SERIALNO']){
                    $isFullyConsumed = true;
                    unset($childDetails[$index]);
                    break;
                }

                if($pEntry['ENABLELOT'] == 'T' || $pEntry['ENABLEBIN'] == 'T'){
                    $pLotKey = $pEntry['LOTNO'].$pEntry['AISLEKEY'].$pEntry['ROWKEY'].$pEntry['BINKEY'];
                    $cLotKey = $cEntry['LOTNO'].$cEntry['AISLEKEY'].$cEntry['ROWKEY'].$cEntry['BINKEY'];

                    if($pLotKey == $cLotKey){
                        $pEntry['QUANTITY'] -= $cEntry['QUANTITY'];
                    }

                    if($pEntry['QUANTITY']==0){
                        $isFullyConsumed = true;
                        unset($childDetails[$index]);
                        break;
                    }
                }
            }
            if($isFullyConsumed){
                continue;
            }

            $pEntry['TRACK_QUANTITY'] = $pEntry['QUANTITY'];
            $availTrackingDetails[$pEntry['DOCENTRYNO']][] = $pEntry;
        }
        return $availTrackingDetails;
    }

    /**
     * @param array $parentEntry
     * @param array $childEntry
     * @param array $backOrderEntry
     */
    function copyToBackOrder($parentEntry, $childEntry, &$backOrderEntry){
		$parentDetails = $parentEntry['TRACKINGENTRIES'];
		$childDetails = $childEntry['TRACKINGENTRIES'];
        $availTrackingDetails = array();

        //
        // get the child entries for each parent entry
        foreach( $parentDetails as $pEntry){
            $isFullyConsumed = false;
            foreach( $childDetails as $cEntry){
                if((isset($pEntry['SERIALNO']) && $pEntry['SERIALNO'] !='') && ($pEntry['SERIALNO'] == $cEntry['SERIALNO'])){
                    $isFullyConsumed = true;
                    break;
                }

				$pLotKey = $pEntry['LOTNO'].$pEntry['AISLEKEY'].$pEntry['ROWKEY'].$pEntry['BINKEY'].$pEntry['SERIALNO'];
				$cLotKey = $cEntry['LOTNO'].$cEntry['AISLEKEY'].$cEntry['ROWKEY'].$cEntry['BINKEY'].$cEntry['SERIALNO'];

				if($pLotKey == $cLotKey){
					$pEntry['QUANTITY'] -= $cEntry['QUANTITY'];
				}

				if($pEntry['QUANTITY']==0){
					$isFullyConsumed = true;
					break;
				}
            }

            if($isFullyConsumed){
                continue;
            }

            $pEntry['TRACK_QUANTITY'] = $pEntry['QUANTITY'];
            $availTrackingDetails[] = $pEntry;
        }

        foreach( $availTrackingDetails as &$tEntry){
            unset($tEntry['RECORDNO']);
            unset($tEntry['DOCENTRYNO']);
        }

        $backOrderEntry['TRACKINGENTRIES'] = $availTrackingDetails;
	}


    /**
     * get the parent id which used serail numbers and which affects onhand quantity in the hierarchy
     *
     * @param string $sourceDocLinekey
     *
     * @return string returns the document id of the parent with serial in the hierarchy/workflow.
     */
    private function getParentWithSerial($sourceDocLinekey)
    {
        $cny = GetMyCompany();
        $qry = "SELECT
                 dh.record#,
                 dh.docid
             FROM
                 dochdr dh
                 LEFT OUTER JOIN (
                     SELECT
                         dpt.cny#,
                         dpt.docparkey,
                         dpt.totalkey,
                         ict.name   total_name,
                         dpt.q_qv
                     FROM
                         docpartotals dpt
                         INNER JOIN ictotal ict ON ict.cny# = dpt.cny#
                                                   AND ict.record# = dpt.totalkey
                     WHERE
                         dpt.cny# =:1
              AND ict.name IN ('ONHAND') 
                         AND dpt.q_qv IN ('Q', 'QV')
                 ) invtotals ON invtotals.cny# =:1
                                AND invtotals.docparkey = dh.docparkey
                 INNER JOIN docentry de ON de.cny# = dh.cny#
                                           AND de.dochdrkey = dh.record#
             WHERE
                 dh.cny# =:1
                 AND ROWNUM = 1
                 AND invtotals.total_name IN ('ONHAND')
                 AND invtotals.q_qv IN ('Q', 'QV')
                 START WITH de.cny# = :1
                        AND de.record# = :2 CONNECT BY NOCYCLE PRIOR de.source_doclinekey = de.record#
                        AND de.cny# = :1 
                        ORDER BY dh.record# ";

        $sourceDocIDWithTrackingInfo = '';
        if ($sourceDocLinekey != '') {
            $res = QueryResult(array($qry, $cny, $sourceDocLinekey));
            $sourceDocIDWithTrackingInfo = $res[0]['DOCID'] ?? '';
        }

        return $sourceDocIDWithTrackingInfo;
    }

    /**
     * If this is a build kit transaction, validate the components:
     * (i) All the tracked components should have at least 1 tracking specification
     * (ii) No tracking specification should appear for unrelated items
     *
     * @param []    $entry The current entry
     * @param []    $itemdetailsArr The tracking details specified for the entry
     * @param bool  $isBuildKitTxn True if this is a build kit transaction, false otherwise
     *
     * @return bool False if there is a component mismatch during a SK build; true if
     *              expected components present, or if not a SK build and, or SK component tracking not enabled
     */
    private function validateStockableKitComponents($entry, $itemdetailsArr, $isBuildKitTxn)
    {
        $ok = true;
        if ( $isBuildKitTxn && StkitDocumentManager::isStockableKitComponentTrackingEnabled() ) {
            // Verify tracking information specified for all tracked components; first, gather specified components.
            $componentsWithSpecifiedTracking = [];
            foreach ( $itemdetailsArr ?? [] as $itemDetails ) {
                if ( $itemDetails['ITEMID'] != $entry['ITEMID']
                     && ! in_array($itemDetails['ITEMID'], $componentsWithSpecifiedTracking, true) ) {
                    $componentsWithSpecifiedTracking[] = $itemDetails['ITEMID'];
                }
            }

            // Do all tracking specificsations pertain to this stockable kit's components?
            foreach ( $componentsWithSpecifiedTracking ?? [] as $componentId ) {
                if ( ! empty($componentId) && ! in_array($componentId, array_keys($this->_itemsRawCache)) ) {
                    // Huh; specification for a component that is not part of the Stockable Kit
                    $ok = false;
                    Globals::$g->gErr->addIAError(
                        'INV-1071', __FILE__ . ':' . __LINE__,
                        "Unable to save document - Invalid Tracking Information provided", [],
                        sprintf('Item \'%1$s\' is not a component of \'%2$s\'', $componentId, $entry['ITEMID']), ['COMPONENT_ID' => $componentId, 'ENTRY_ITEMID' => $entry['ITEMID']],
                        'Omit tracking details for this item', []
                    );
                }
            }
        }
        return $ok;
    }
}
