<?
import('InventoryReporter');

/**
 * Class InventoryCustVendReporter
 */
class InventoryCustVendReporter extends InventoryReporter
{

    /**
     * @param array $params
     */
    function __construct($params)
    {

        $params['whereclause']['vend'] = " ((docpar.latestversionkey is null and 
											upper(docpar.docclass) = 'ORDER' and 
											upper(docpar.sale_pur_trans) = 'P' and
											upper(docpar.in_out) = 'I' and 
											upper(dochdr.state) in ('O','P','B')) or
											(docpar.latestversionkey is not null and
											upper(latestversion.docclass) = 'ORDER' and 
											upper(latestversion.sale_pur_trans) = 'P' and
											upper(latestversion.in_out) = 'I' and 
											upper(dochdr.state) in ('O','P','B'))) ";

        $params['whereclause']['datefilter'] = " dochdr.whendue >= :4 and 
												 dochdr.whendue <= :5 and ";

        $params['2stage'] = 'true';
        //This is for Customer Backlog report 
        //and if the documents are converted by line
        $params['whereclause']['licfilter'] = " (docentry.quantity-docentry.qty_converted) != 0 and ";
        $params['whereclause']['licselect'] = " or (dochdr.state = 'B') ";
        parent::__construct($params);
    }


    /**
     * @return bool
     */
    function ValidateReport()
    {

        // we don't require a date, so don't verify the dates
        $this->ParamTweaks();
        return true;
    }
}

