<?
require_once 'util.inc';
import('InventoryStatusReporter');

class InvBulkPrintReport extends InventoryStatusReporter
{
    /**
     * @param array $params
     */
    public function __construct($params)
    {
        parent::__construct(
            INTACCTarray_merge(
                $params, 
                array( 
                'report' => 'invbulkprint', 
                'ops'     =>    array(
                                    'inv/lists/invdocument/view',
                                    'inv/lists/warehouse/view',
                                    'inv/lists/contact',
                                    ),
                'deliverop' => 'inv/lists/invdocument/view',
                '2stage'    => true,
                )
            )
        );
    }


    /**
     * @return bool
     */
    public function DoQuery()
    {
        $this->ValidateReport();

        $params = $this->params['safe'];
        $fromitemid                = $params['FROMITEMID'];
        $toitemid                = $params['TOITEMID'];
        $doctype                = $params['trans'];
        $dt1                    = $params['dt1'];
        $dt2                    = $params['dt2'];


        $cny = GetMyCompany();
        //docentry.warehousekey as entityid,
         $Q1= "SELECT	
				dochdr.record# dochdrkey, 
				dochdr.whencreated, 
				to_char(dochdr.whencreated, 'mm/dd/yyyy') docdate, 
				dochdr.ponumber, 
				docpar.docid doctype, 
				dochdr.whendue, 
				sum(docentry.quantity*docentry.price) totalamt,
				dochdr.docid docnokey,
				docpar.category,
				contact.email1,
				docentry.warehousekey as entityid,
				docentry.warehousekey as entity
		FROM	
				dochdrmst dochdr, 
				docparmst docpar, 
				docentry docentry,
				contact
		WHERE	
				docpar.record# (+) = dochdr.docparkey and
				contact.record# (+) = dochdr.billtokey and
				docpar.sale_pur_trans = ? and
				dochdr.whencreated BETWEEN ? and  ? and
				docentry.itemkey BETWEEN ? and ? and
				docentry.dochdrkey = dochdr.record# and 
				docpar.cny# = $cny and 
				dochdr.cny# = $cny and
				dochdr.state not in ('I','S','A', 'X', 'R') and
				docentry.cny# = $cny and
				contact.cny# (+) = $cny 
				";
        if ($doctype !='%') {
            $CRITERIA = array('I', $dt1, $dt2, $fromitemid, $toitemid, $doctype);
             $ARGTYPES = array( 'text', 'date', 'date', 'text','text','text' );
            $Q3 = " and docpar.docid like ? ";
        } else {
            $Q3 = "";
            $CRITERIA = array('I', $dt1, $dt2, $fromitemid, $toitemid);
             $ARGTYPES = array( 'text', 'date', 'date', 'text','text' );
        }


        $Q2 = "	GROUP BY 
				dochdr.record#, 
				dochdr.whencreated, 
				to_char(dochdr.whencreated, 'mm/dd/yyyy'),
				dochdr.ponumber, 
				docpar.docid, 
				dochdr.whendue, 
				dochdr.docid, 
				docpar.category,
				contact.email1,
				docentry.warehousekey,
				docentry.warehousekey
		ORDER BY 
				dochdr.whencreated, 
				dochdr.record#";


        $qrystring = $Q1 . $Q3 . $Q2;

        $docs = $this->_QM->DoCustomQuery(array('QUERY'=>$qrystring, 'ARGTYPES'=>$ARGTYPES), $CRITERIA, true);
        $this->_docs = $docs;
        return true;
    }

    /*
    tgw - comment out - why do I need this in the bulk print for inventory?


    function GenerateJavascript($params){
    // this is overridden because we need to go to a lister from the price list reports, not an editor


    $_sess = Session::getKey();
    return "	
    function doselect(form, type, idtype) {
    value = false;
    for(i=0; ; i++) {
				id = form.elements['.' +idtype+'['+i+']'];
				if(id == null) {
					break;
				}
				check = form.elements['.'+type+'['+id.value+']'];
				if(i == 0) {
					value = ! check.checked;
				}
				check.checked = value;
    }
    return;
    }
    ";
    }
    */
}


