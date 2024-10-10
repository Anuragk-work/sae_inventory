<?

/**
 * Class AvailableInventoryManager
 */
class AvailableInventoryManager extends EntityManager
{

    /** @var string $columnConcatinationString */
    private $columnConcatinationString = '-&-';

    const API_QUERY_ALIAS = 'API_QUERY_ALIAS__';

    /**
     * Please dont alter the order of fields in array
     * @var string[]
     */
    private $fieldsToAdd = [
        'DATERECEIVED', 'ITEMID', 'WAREHOUSEID', 'BINID', 'AISLE', 'ZONE', 'ROW', 'UOM', 'SERIALNO', 'LOTNO', 'EXPIRATIONDATE'
    ];

    /**
     * @param array $params
     */
    public function __construct($params = array())
    {
        parent::__construct($params);
    }

    /**
     *  standard get() but with a twist:
     * @param string $ID
     * @param null|array $fields
     *
     * @return array|false
     */
    function Get($ID, $fields=null)
    {
        $obj = parent::get($ID, $fields);
        // adding logic hear to fix orphaned document.
        if (is_array($obj)) {
            $listToReturn[] = $obj;
            $params = null;
            $this->checkForOrphanedDocuments($listToReturn, $params);
            return $listToReturn[0];
        }
        return $obj;
    }

    /**
     * Return a list of entities
     *
     * @param array $params    a structure used to build the custom query
     * @param bool  $_crosscny if true do not add the var.cny# = ... code
     * @param bool  $nocount   don't generate a count column
     *
     * @return array[] $newResult  result of query
     */
    function GetList($params = [], $_crosscny = false, $nocount = true)
    {
        $this->addFieldsToSelectToCheckQuantity($params);

        $listToReturn = parent::GetList($params, $_crosscny, $nocount);

        if (Util::countOrZero($listToReturn) > 0) {
            $this->checkForOrphanedDocuments($listToReturn, $params);
        }

        return $listToReturn;
    }


    /**
     * Function to add list of fields required to select.
     * @param $params
     * @return void
     */
    private function addFieldsToSelectToCheckQuantity(&$params)
    {
        // Are they in the select statements?
        foreach ($this->fieldsToAdd as $field) {
            if (!in_array($field, $params['selects'])) {
                $params['selects'][] = $field;
            }
        }
        // check if its already asked
        if (!in_array('QUANTITYLEFT', $params['selects'])) {
            $params['selects'][] = 'QUANTITYLEFT';
        }
        $params['selects'] = array_values($params['selects']);  // renumber the entries
    }


    /**
     * Function will query Sales transactions that are effecting quantity on hand but dont have source docentrykey key and
     * balance the $listToReturn quantity by looping through all the records.
     *
     * This should fix the issue of credit notes (sales return) transactions having quantity left populated
     * even in case of source incoming transactions are reversed or deleted not even populated since there is no source.
     *
     * Again ideal way to fix this is by adding query logic to view that will cause QA overhead and needs schema change.
     * We are doing it hear to avoid testing overhead but this my add to response time when querying through API.
     *
     * @param $listToReturn
     * @param $params
     * @return void
     */
    private function checkForOrphanedDocuments(&$listToReturn, &$params)
    {
        $items = [];
        $warehouse = [];
        $fieldWithIndexPair = [];
        $selectQuantityLeftFld = 'QUANTITYLEFT';
        // we need to collect the field index since REST API is using columnaliases
        if($params != null) {
            foreach ($this->fieldsToAdd as $fieldToSeach) {
                $fieldWithIndexPair[$fieldToSeach] = array_search($fieldToSeach, $params['selects']);
            }
            // get quanatiy left index
            $fieldWithIndexPair[$selectQuantityLeftFld] = array_search('QUANTITYLEFT', $params['selects']);

            // finding the columnaliases for quanatityleft
            if (isset($params['columnaliases']) && isset($params['columnaliases'][$fieldWithIndexPair['QUANTITYLEFT']])) {
                $selectQuantityLeftFld = $params['columnaliases'][$fieldWithIndexPair['QUANTITYLEFT']];
            }
        }
        // preping in claus with item and warehouse
        foreach ($listToReturn as $recordArray) {
            if($params != null) {
                $record = array_values($recordArray);
                $itemId = "'" . $record[$fieldWithIndexPair['ITEMID']] . "'";
                $warehouseId = "'" . $record[$fieldWithIndexPair['WAREHOUSEID']] . "'";
            }else{
                $itemId = "'" . $recordArray['ITEMID'] . "'";
                $warehouseId = "'" . $recordArray['WAREHOUSEID'] . "'";
            }
            // we dont need duplicate itemIds
            if (!in_array($itemId, $items)) {
                $items [] = $itemId;
            }
            // we dont need duplicate warehouseIds
            if (!in_array($warehouseId, $warehouse)) {
                $warehouse [] = $warehouseId;
            }
        }
        $itemClause = '(' . implode(', ', $items) . ')';
        $warehouseClause = '(' . implode(', ', $warehouse) . ')';

        $selectStrings = '(dce.datein || \'' . $this->columnConcatinationString . '\' ||
                                 dce.itemkey || \'' . $this->columnConcatinationString . '\' ||
                                 dce.whsekey || \'' . $this->columnConcatinationString . '\' ||
                                 bin.binid|| \'' . $this->columnConcatinationString . '\'  ||
                                 aisle.aisleid || \'' . $this->columnConcatinationString . '\'  ||
                                 zone.zoneid || \'' . $this->columnConcatinationString . '\' ||    
                                 icrow.rowkey || \'' . $this->columnConcatinationString . '\' ||                             
                                 icuom.unit || \'' . $this->columnConcatinationString . '\'  ||
                                 dce.serialno || \'' . $this->columnConcatinationString . '\'  ||
                                 dce.lotno || \'' . $this->columnConcatinationString . '\'  ||
                                 dce.expirationdate) as ItemsRecord,';

        $queryQuantityNegativeDocument = "select "
            . $selectStrings . "
                                 sum(quantity) quantity
                                 FROM
            docentrycost dce
			 LEFT JOIN icbin bin ON bin.cny# = dce.cny#
                           AND bin.record# = dce.binkey
    LEFT JOIN iczone zone ON zone.cny# = bin.cny#
                           AND zone.record# = bin.zonekey
    LEFT JOIN icaisle aisle ON aisle.cny# = bin.cny#
                           AND aisle.record# = bin.aislekey
    LEFT JOIN icrow icrow ON icrow.cny# = bin.cny#
                           AND icrow.record# = bin.rowkey
    INNER JOIN icitem it ON it.cny# = dce.cny# AND it.itemid = dce.itemkey
    INNER JOIN icuomgrp ON icuomgrp.cny# = it.cny#  AND icuomgrp.record# = it.uomgrpkey
    INNER JOIN icuom ON icuom.cny# = icuomgrp.cny#  AND icuom.grpkey = icuomgrp.record#
    LEFT  JOIN icwarehouse iw ON iw.cny# = dce.cny#  AND iw.warehouseid = dce.whsekey
        WHERE
            dce.in_out = 'O'
            AND dce.affects_inventory IN (
                'V',
                'QV'
            )
            AND dce.adjdocentrycostkey IS NULL
			AND dce.docentrycostkey IS NULL
			AND dce.cny# = :1
			AND dce.itemkey IN " . $itemClause . "
			AND dce.whsekey IN " . $warehouseClause . "
			AND icuom.isbase = 'T'
        GROUP BY
            dce.cny#,
            dce.datein,
            dce.itemkey,
            dce.whsekey,
			bin.binid,
            aisle.aisleid,
            icrow.rowkey,
			zone.zoneid,
			icuom.unit,
			dce.lotno,
            dce.serialno,
            dce.expirationdate";

        $args[0] = $queryQuantityNegativeDocument;
        $args[1] = GetMyCompany();

        // if query is malformed QueryResult method is handling it and showing an error
        // so we dont need to add extra validation for query errors
        $salesOrderWithNegativeQuantity = QueryResult($args);

        //if there are sales invoices with docentrykeys null (i.e. sales invoices that are responsible for -ve quantity)
        //loop all the entries and balance the quantity to fix the  quantity left for incoming transactions in $listToReturn
        if (Util::countOrZero($salesOrderWithNegativeQuantity) > 0) {

            $itemWithTotalNegativeQuantity = [];
            foreach ($salesOrderWithNegativeQuantity as $orderWithNegativeQuantity) {
                $itemWithTotalNegativeQuantity [$orderWithNegativeQuantity['ITEMSRECORD']] = $orderWithNegativeQuantity['QUANTITY'];
            }

            if (Util::countOrZero($itemWithTotalNegativeQuantity) > 0) {
                for ($i = 0, $_i_ct = Util::countOrZero($listToReturn); $i < $_i_ct; $i++) {
                    $listToReturnValues = array_values($listToReturn[$i]);
                    $key = '';

                    // pairing the item, bin, warehouse, lot, row, aisle, serial mapping
                    foreach ($this->fieldsToAdd as $field) {
                        if ($field !== 'QUANTITYLEFT') {
                            if ($key === '') {
                                $key = $params != null ? $listToReturnValues[$fieldWithIndexPair[$field]] : $listToReturn[$i][$field];
                            } else {
                                $key .= $this->columnConcatinationString . ($params != null ? $listToReturnValues[$fieldWithIndexPair[$field]] : $listToReturn[$i][$field]);
                            }
                        }
                    }

                    if ($listToReturn[$i][$selectQuantityLeftFld] > 0 &&
                        key_exists($key, $itemWithTotalNegativeQuantity) &&
                        $itemWithTotalNegativeQuantity[$key] > 0) {
                        if ($listToReturn[$i][$selectQuantityLeftFld] >= $itemWithTotalNegativeQuantity[$key]) {
                            $listToReturn[$i][$selectQuantityLeftFld] = $listToReturn[$i][$selectQuantityLeftFld] - $itemWithTotalNegativeQuantity[$key];
                            $itemWithTotalNegativeQuantity[$key] = 0;
                        } else {
                            $itemWithTotalNegativeQuantity[$key] = $itemWithTotalNegativeQuantity[$key] - $listToReturn[$i][$selectQuantityLeftFld];
                            $listToReturn[$i][$selectQuantityLeftFld] = 0;
                        }
                    }
                }
            }

        }

    }


}
