<?
import('InventoryReporter');

/**
 * Class InventoryCustVendShipHistReporter
 */
class InventoryCustVendShipHistReporter extends InventoryReporter
{
    /**
     * @param array $params
     */
    function __construct($params)
    {
        $params['report'] = 'invshiphist';
        $params['2stage'] = 'true';
        $params['whereclause']['vend'] = " ((docpar.latestversionkey is null and docpar.in_out = 'I' and 
								(docpar.updinv = 'Q' or docpar.updinv = 'T') and docpar.sale_pur_trans = 'P') or 
								(docpar.latestversionkey is not null and latestversion.in_out = 'I' and 
								(latestversion.updinv = 'Q' or latestversion.updinv = 'T') and
								latestversion.sale_pur_trans = 'P')) ";

        
        $params['whereclause']['cust'] = " ((docpar.latestversionkey is null and docpar.in_out = 'D' and
											(docpar.updinv = 'Q' or docpar.updinv = 'T') and docpar.sale_pur_trans = 'S') or 
											(docpar.latestversionkey is not null and latestversion.in_out = 'D' and
											(latestversion.updinv = 'Q' or latestversion.updinv = 'T') and
											latestversion.sale_pur_trans = 'S')) ";
        
        $params['whereclause']['datefilter'] = " dochdr.whencreated >= :4 and 
												 dochdr.whencreated <= :5 and ";

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

