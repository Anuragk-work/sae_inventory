<?
import('InventoryReporter');

/**
 * Class InventoryStatusReporter
 */
class InventoryStatusReporter extends InventoryReporter
{
   /**
     * @param array $params
     */
    function __construct($params)
    {
        parent::__construct($params);
    }


    /**
     * @return array
     */
    function DoMap()
    {
        /*
        $encodethese = array(
         'DOCHDRKEY',
         'BILLTOKEY',
         'SHIPTOKEY',
        );
        */
        $uicategory = $this->params['safe']['UICATEGORY'];
        $RepMap = array();
        $docsMap = array();
        $totals = 0;
        $locref = $this->params['safe']['locs'][0];
        $invoicecounter = 0; // this counter goes in the hidden invoice field that is used by the *select all* link in the inv bulk print report
        
        if($this->_ismcpEnabled) {
            $baseCurrency = GetBaseCurrency();
        }

        foreach($this->_docs as $row){
            $loclink = $row['DOCLOC'] ?? $row['MELOCATIONKEY'] ?? $locref;

            $docID = urlencode(addslashes($row['DOCNOKEY']));
            //			$row['DOCHREF'] 	= "javascript:drilldown(0,'" . urlencode($row['DOCNOKEY']) . "');";
            $row['DOCHREF']         = "javascript:drilldown(0,'$docID', '$loclink');";

            $row['ENTITYHREF']     = "javascript:drilldown(1,'" . urlencode($row['ENTITYID']) . "', '$row[ENOWNERLOC]');";
            $row['BILLTOHREF']     = "javascript:drilldown(2,'" . urlencode($row['BILLTOKEY']) . "');";
            $row['SHIPTOHREF']     = "javascript:drilldown(2,'" . urlencode($row['SHIPTOKEY']) . "');";

            // must add to totals before we change the thing to currency!
            $totals = $totals + $row['TOTALAMT'];
            // this killed the report formatting
            //$row['TOTALAMT'] = glFormatCurrency(iround($row['TOTALAMT'],2));

            if($this->_ismcpEnabled) {
                
                if($row['CURRENCY'] =='') {
                    /** @noinspection PhpUndefinedVariableInspection */
                    $row['CURRENCY'] = $baseCurrency;
                    $row['TRXAMT'] = $row['TOTALAMT'];
                }

                // this killed the report formatting
                //if(isset($row['TRXAMT'])){
                //	$row['TRXAMT'] = glFormatCurrency($row['TRXAMT']);
                //}
            }
            $docsMap[$row['DOCHDRKEY']] = $row;
        }

        // loop thru and put in the invoice counter for each document
        foreach($docsMap as $doc){
            $doc['INVOICECOUNTER'] = $invoicecounter++;
            $newdoc[] = $doc;
        }
        /** @noinspection PhpUndefinedVariableInspection */
        $docsMap = ( $newdoc ?? [] );

        if (count($docsMap)>0) {
            $RepMap['PODOCS']    = $docsMap;
            //$TotalMap['TOTALS'][0]= array('GRNTOTALAMT'=> glFormatCurrency(iround($totals,2)) );
            $TotalMap['TOTALS'][0]= array('GRNTOTALAMT'=> $totals) ;
        }
        else{
            $RepMap['PODOCS'][0]= array('NODATA'=>'1');
        }

        $lines                            = $this->InvCommonHeader();
        $lines['report']["0"]['ismcpEnabled'] = $this->_ismcpEnabled;
        $lines['report']["0"]['STAT']    = $RepMap;
        
        // don't show totals if they picked all, it doesn't make sense
        if (count($docsMap)>0 && $uicategory != "%") {
            /** @noinspection PhpUndefinedVariableInspection */
            $lines['report']["0"]['TOTALS']    = $TotalMap;
        }

        $lines['report']["0"]['prevprint'] = $this->params['safe']['prevprint'];
        $lines['report']["0"]['BILLTOLABEL'] = 'IA.BILL_TO';

        return $lines;
    }

}