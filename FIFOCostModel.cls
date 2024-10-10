<?php
/**
 * Manager class for health check cost computation
 *
 * @file FIFOCostModel.cls
 * @author Sandeep Pasunuri <spasunuri@intacct.com>
 * @copyright 2015 Intacct Corporation, All Rights Reserved
 */

class FIFOCostModel { // extends CostModel {  PHP71 cleanup: there IS NO CostModel!  There is a zero-byte file CostModel.cls, but....

    /**
     * @var array|bool  $fifoCostLineItems
     */
    var $fifoCostLineItems = array();

    /**
     * @param string $item
     * @param string $warehouse
     * @param string $as_on
     */
    public function fetchCostLines($item, $warehouse, $as_on)
    {

        $query[0] = "
            select
                d.whencreated AS docdate,
                d.record# AS drec,
                de.record# AS derec,
                dec.record# AS decrec,
                dec.docentrycostkey AS decref,
                d.docid,
                d.docparkey,
                dec.IN_OUT AS inout,
                i.itemtype,
                de.itemkey item,
                dec.itemkey comp,
                de.warehousekey,
                decode(dec.in_out, 'I', 1, -1) * dec.quantity AS quantity,
                d.subtotal,
                d.total,
                0 as docsubtotal,
                0 as entrysubtotal,
                0 as endvalue,
                0 as avgcost,
                0 as whseavgcost,
                0 as histcost
            from
             dochdrmst d, docentrymst de, docentrycost dec, icitem i
            where
                d.cny#=:1
                AND dec.cny#=:1
                AND i.cny#=:1
                AND de.cny#=:1
                AND i.itemid=dec.itemkey
                AND i.cost_method = 'F'
                AND dec.docentrykey=de.record#
                AND dec.affects_inventory IN ('V','QV')
                AND de.dochdrkey=d.record#
        ";
        $query[1] = GetMyCompany();
        $argCounter = 2;

        if ($item != '') {
            $query[0] .= " AND i.itemid=:" . $argCounter++;
            $query[] = $item;
        }

        if ($warehouse != '') {
            $query[0] .= " AND dec.whsekey=:" . $argCounter++;
            $query[] = $warehouse;
        }

        if ($as_on != '') {
            $query[0] .= " AND d.whencreated>=TO_DATE(:" . $argCounter . ",'mm/dd/yyyy')"; // Last instance of $argCounter so no ++
            $query[] = $as_on;
        }

        $query[0] .= " ORDER BY dec.itemkey, de.warehousekey, d.whencreated,dec.in_out, d.record#, de.record#, dec.record#";

        $this->fifoCostLineItems = QueryResult($query);
    }
}