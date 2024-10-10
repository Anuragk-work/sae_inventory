<?php



class InventoryWQOrderLister extends NLister
{


    /**
     * InventoryWQOrderLister constructor.
     *
     *
     */
    public function __construct()
    {
        $fields = array('DOCNO', 'WAREHOUSEID', 'SHIPTO.COMPANYNAME', 'CUSTOMERID', 'CUSTOMERNAME',
            'NUMBEROFLINES', 'STATUS', 'PCTFULFILLABLE', 'TERMNAME', 'SHIPVIA', 'WHENCREATED', 'ASSIGNED'
            );
        /** @var InventoryWQOrderManager $em */
        $em = $this->entityMgr;
        /* if ($em->areShipDatesEnabled()) {
            $fields = array_merge($fields, array('SHIPBYDATE', 'SHIPPEDDATE', 'NEEDBYDATE', 'DONOTSHIPBEFOREDATE',
                    'DONOTSHIPAFTERDATE', 'CANCELAFTERDATE' ));
        }*/
        parent::__construct(
            array(
                'entity' => 'inventorywqorder',
                'fields' => $fields,
                'title' => _('Fulfillment: test view by order'),
                // 'enablecheck' => true,
                'id' => 'ICWQORDERID',
                'disableadd' => true,
                'disableedit' => true,
                'entitynostatus' => true,
                'hide_cancel' => true,
            )
        );
    }

}
