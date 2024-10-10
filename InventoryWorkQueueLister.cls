<?


class InventoryWorkQueueLister extends NLister
{


    /**
     * InventoryWorkQueueLister constructor.
     *
     *
     */
    protected $additionalTokens = [
        "IA.FULFILLMENT_READY_FOR_FULFILLMENT","IA.UNRESERVE_ORDER_LINES","IA.CREATE_WORKLIST","IA.CREATE_WORKLIST_BY_ORDER"];

    public function __construct()
    {
        parent::__construct(
                array(
                    'entity'            =>  'inventoryworkqueue',
                    'fields'            =>  array('DOCID', 'DOCNO', 'ITEMID', 'LINENO',
                                                  'WAREHOUSEID', 'QUANTITY', 'ORDERDATE', 'TASKLISTID'),
                    'sortcolumn'        => 'dochdr.DOCID, inventoryworkqueue.TASKLISTID',
                    'title'             => 'IA.FULFILLMENT_READY_FOR_FULFILLMENT',
                    'enablecheck'   => true,
                    'disableadd'    => true,
                    'disableedit' => true,
                    'bulkactions' => true,
                    'id' 	    => 'RECORDNO',
                )
        );
    }

    /**
     * This is an override of the GetList() in NLister.  It is very similar to the GetList() in the manager,
     *  but is, in fact, different (!)
     *
     *
     *  - if an error is generated, throw it as an exception.  The caller only responds to exceptions, not errors.
     *
     * @param array  $querySpec
     * @param string $querytype
     *
     * @return string[][]
     */
    function GetList($querySpec, $querytype = 'normal')
    {
        $res = parent::GetList($querySpec, $querytype);
        if (is_array($res)) {
            foreach ($res as $index => $row) {
                if (isset($row['PLACE'])) {
                    // Turn into the local language:
                    $place = $row['PLACE'];
                    if (isset($this->entityMgr->staticQueueInformationTable[$place])) {
                        $res[$index]['PLACE'] = $this->entityMgr->staticQueueInformationTable[$place]['NAME']; // change the name
                    }
                }
            }
        }

        return $res;
    }

    /**
     * @param string $action
     * @param string $url
     * @param string $key
     * @param array $postArgs
     *
     * @return string
     */
    protected function getBulkActionJSFunction(string $action, string $url, string $key, array $postArgs): string
    {
        $args = XMLUtils::xmlSpecialChars(json_encode($postArgs));
        $msg = $this->getBulkActionConfirmMessage($action);
        return " onclick='return postBulkActionFulFillment(\"$url\", \"$key\", \"$msg\", $args, \"$action\" ); hideQXLoader();'";
    }

    /**
     * generate the bulk action buttons
     * @return string
     */
    protected function genBulkActionButtons() : string
    {
        $url = $this->calcBulkActionUrl(BulkAction::UNRESERVEORDERLINE);
        $bulkButtons = "<bulk id='unreserveorderlines'>$url</bulk>";


        $url = $this->calcBulkActionUrl(BulkAction::CREATEWORKLIST);
        $bulkButtons .= "<bulk id='createworklist'>$url</bulk>";

        $url = $this->calcBulkActionUrl(BulkAction::CREATEWORKLISTBYORDER);
        $bulkButtons .= "<bulk id='createworklistbyorder'>$url</bulk>";
        return $bulkButtons;
    }

    /**
     * @param string $action
     *
     * @return string
     */
    protected function getBulkActionLabel(string $action): string
    {
        switch ($action) {
            case BulkAction::UNRESERVEORDERLINE:
                $label = GT($this->textMap,'IA.UNRESERVE_ORDER_LINES');
                break;
            case BulkAction::CREATEWORKLIST:
                $label = GT($this->textMap,'IA.CREATE_WORKLIST');
                break;
            case BulkAction::CREATEWORKLISTBYORDER:
                $label = GT($this->textMap,'IA.CREATE_WORKLIST_BY_ORDER');
                break;
            default:
                $label = parent::getBulkActionLabel($action);
        }

        return $label;
    }

    /**
     * Override to assign labels to bulk action buttons.
     * @param string $action
     *
     * @return int
     */
    protected function getBulkActionOp(string $action): int
    {
        $op = parent::getBulkActionOp($action);
        return  $op === 0 ? GetOperationId("inv/lists/inventoryworkqueue") : $op;
    }




}

