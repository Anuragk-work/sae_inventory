<?
/**
 * class for LIFO/FIFO costing logic in SCM
 * 
 * @author    Senthil <skumar@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

class LIFOFIFOCosting extends Costing
{

    /**
     * @param array $itemIDs
     * @param string $warehouseID
     *
     * @return array
     * @throws Exception
     */
    public static function getCostLayers($itemIDs, $warehouseID)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;

        $itemMgr = $gManagerFactory->getManager('item');
        $params = array(
                'selects' => array('ITEMID', 'COST_METHOD'),
                'filters' => array(array(array('ITEMID', 'IN', $itemIDs))),
            );

        $recs = $itemMgr->GetList($params);

        $fifoItems = array();
        $lifoItems = array();

        foreach ($recs as $rec) {
            if ($rec['COST_METHOD'] == 'FIFO') {
                $fifoItems[] = $rec['ITEMID'];
            } else if ($rec['COST_METHOD'] == 'LIFO') {
                $lifoItems[] = $rec['ITEMID'];
            }
        }

        $stmt = array();
        $stmt[]
            = "SELECT
                    dc.record#,
                    dc.itemkey,
                    dc.datein,
                    dc.unitcost cost,
                    dc.quantity,
                    dc.qtyleft
                FROM
                    docentrycost dc
                    INNER JOIN docentrymst de ON
                        de.cny# = dc.cny#
                    AND
                        de.record# = dc.docentrykey
                    INNER JOIN dochdrmst dh ON
                        dh.record# = de.dochdrkey
                    AND
                        dh.cny# = de.cny#
                    AND
                        dh.state NOT IN (
                            'I','S','A','X','R'
                        )
                WHERE
                    dc.whsekey =:2
                AND
                    dc.qtyleft > 0
                AND
                    dc.in_out = 'I'
                AND
                    dc.affects_inventory IN (
                        'V','QV'
                    )
                AND
                    dc.cny# =:1";

        $stmt[] = GetMyCompany();
        $stmt[] = $warehouseID;

        $costDetails = array();

        if (!empty($fifoItems)) {
            $fifoStmt = PrepINClauseStmt($stmt, $fifoItems, ' and dc.itemkey');
            $fifoStmt[0] .= " ORDER BY dc.itemkey, dc.datein asc, dc.record# asc";

            $fifoRes = QueryResult($fifoStmt);

            foreach ($fifoRes as $res) {
                $costDetails[$res['ITEMKEY']][] = $res;
            }
        }

        if (!empty($lifoItems)) {
            $lifoStmt = PrepINClauseStmt($stmt, $lifoItems, ' and dc.itemkey');
            $lifoStmt[0] .= " ORDER BY dc.itemkey, dc.datein desc, dc.record# desc";

            $lifoRes = QueryResult($lifoStmt);

            foreach ($lifoRes as $res) {
                $costDetails[$res['ITEMKEY']][] = $res;
            }
        }

        return $costDetails;
    }

}