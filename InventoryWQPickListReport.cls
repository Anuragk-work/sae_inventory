<?
define('DEFAULT_INVPRECISION', 2);

class InventoryWQPickListReport extends InventoryReporter
{
    /**
     * @var string[][] $_picklistlines
     */
    private $_picklistlines;

    /**
     * @var string[][] $_reportselection
     */
    private $_reportselection;

    /**
     * @var string $_groupbylabel
     */
    private $_groupbylabel;


    /**
     * @param array $params
     */
    function __construct($params)
    {
        parent::__construct(
            INTACCTarray_merge(
                $params, array(
                    'report' => 'inventorywqpicklist',
                    'ops'    => array(
                        'so/lists/item/view',
                        'inv/lists/invdocument/view',
                        'so/lists/sodocument/view',
                        'po/lists/podocument/view',
                        'inv/lists/inventorywqorder',
                    ),
                    '2stage'    => true,
                )
            )
        );
        $this->params['NOREPORTLOCCHECK'] = true;
    }
// changes here

    /**
     *
     * @param array $recordsToPrint optional list of docentry record#s
     * @param array $reportSelection
     *
     * @return bool
     */
    function DoQuery( $recordsToPrint = [], $reportSelection = [])
    {
        $ok = true;
        $this->_reportselection = $reportSelection;
        $dataToPrint           = $this->getDataForPrinting($recordsToPrint);
        $this->_picklistlines = $this->formatDataForPrinting($dataToPrint);
        if ( empty($this->_picklistlines )) {
            $ok = false;
        }
        return $ok;
    }

    /**
     * @return array[]
     */
    function DoMap()
    {
        $printingLines =[];
        $pritingData = $this->_picklistlines;
        $reportSelection = $this->_reportselection;
        switch($reportSelection['GROUPBY']) {
            case "assignedto":
                $groupBy = "ASSIGNEDTO";
                $this->_groupbylabel = 'IA.ASSIGNED_TO';
                break;

            case "customer":
                $groupBy = "CUSTOMERID";
                $this->_groupbylabel = 'IA.CUSTOMER_ID';
                break;

            case "shippedto":
                $groupBy = "SHIPTOCONTACT";
                $this->_groupbylabel = 'IA.SHIP_TO';
                break;

            default:
                $groupBy = "DOCID";
                $this->_groupbylabel = 'IA.DOCUMENT_ID';
        }
        $docarr = [];
        //starting the for loop for all the docentrycost record found by the query
        foreach ( $pritingData as $printVal) {
            if(empty($docarr[$printVal[$groupBy]])){
                $docarr[$printVal[$groupBy]]['DOCID']= $printVal[$groupBy];
                $docarr[$printVal[$groupBy]]['TQTY'] = ibcadd(0, $printVal['QUANTITY'], 2, true);
                $docarr[$printVal[$groupBy]]['DETAILS'][]= $printVal;
            } else {
                $docarr[$printVal[$groupBy]]['TQTY'] = ibcadd($docarr[$printVal[$groupBy]]['TQTY'], $printVal['QUANTITY'], 2, true);
                $docarr[$printVal[$groupBy]]['DETAILS'][]= $printVal;
            }
        }
        $finalarr = array_values($docarr);

        if (count($finalarr)==0) {
            $finalarr['NODATA'][0]= array('NODATA'=>'1');
        }else{
            //grand totals maps to quantity
            $headerData = $this->InvCommonHeader();

            foreach ($finalarr as $index => $grpValue) {
                $printingLines[$index] = $this->InvCommonBody($headerData, [$grpValue]);
            }

        }

        return $printingLines;
    }


    /**
     * prepareHeader for ptinting the document
     *
     * @return array
     */
    function InvCommonHeader()
    {
        $lines = parent::InvCommonHeader();
        $lines['report'][0]['trackinginfo']      =  'N';

        if(isset($this->_reportselection['TRACKINGINFO']) && $this->_reportselection['TRACKINGINFO'] == "true"){
            $lines['report'][0]['trackinginfo'] = 'Y';
            $lines['report'][0]['showtrackinginfo'] = 'true';
        }

        if(isset($this->_reportselection['ORDERID']) && $this->_reportselection['ORDERID'] == "true"){
            $lines['report'][0]['orderid'] = 'Y';
            $lines['report'][0]['showorderid'] = 'true';
        }

        if(isset($this->_reportselection['SHIPDATE']) && $this->_reportselection['SHIPDATE'] == "true"){
            $lines['report'][0]['shipdate'] = 'Y';
            $lines['report'][0]['showshipdate'] = 'true';
        }

        $lines['report'][0]['groupbylabel'] = $this->_groupbylabel;
        $lines['report'][0]['reporttime'] = GetCurrentTZTime();

        return $lines;
    }

    /**
     *      Get the data to be printed
     *
     * @param   array   $rows   Rows from the client, sanitized; we mostly care about the ICWQORDERID
     *
     * @return array            inventorywqdetail records to be printed
     */
    private function getDataForPrinting($rows)
    {
        $printData         = [];
        $docEntriesToprint = [];
        $lineLevelPrinting = false;
        $iwqoManager = Globals::$g->gManagerFactory->getManager("inventorywqorder");
        foreach ($rows as $oneRow) {
            $iwqorderid  = $oneRow['ICWQORDERID'];
            $docEntries  = $iwqoManager->get($iwqorderid);
            if ($docEntries === false) {
                $printData = [];
                break;
            }
            $printData[] = $docEntries;
            if (isset($oneRow['DOCENTRYKEY']) && $oneRow['DOCENTRYKEY'] != '') {
                $lineLevelPrinting = true;
                break;
            }
        }

        //For the Line level printing we need to handle it seperately because it is only one order we are printing,
        //but may be selected lines so, we only need to consider the lines which they are trying to print fro the whole
        // order.
        if($lineLevelPrinting){
            foreach ($rows as $oneRow) {
                $docEntriesToprint[] = $oneRow['DOCENTRYKEY'];
            }

            foreach ($printData[0]['ENTRIES'] as $index => $printEntries) {
                if (!in_array($printEntries['DOCENTRYKEY'], $docEntriesToprint)) {
                    unset($printData[0]['ENTRIES'][$index]); // we want this
                }
            }
            $printData[0]['ENTRIES'] = array_values($printData[0]['ENTRIES']);
        }

        return $printData;
    }


    /**
     *      Get the data to be printed
     *
     * @param   array   $rows   Rows from the client, sanitized; we mostly care about the ICWQORDERID
     *
     * @return array            inventorywqdetail records to be printed
     */
    private function formatDataForPrinting($rows)
    {
        $printData =[];
        if(!empty($rows) && count($rows) > 0){
            $index = 0;
            //need a different logic here
            foreach ($rows as $data) {
                $docID = $data['DOCID'];
                $customerID = $data['CUSTOMERID'];
                // By deault we are populating not assigned for the unassigned orders
                $assignedTo = (isset($data['ORDERASSIGNED']) && $data['ORDERASSIGNED'] != '') ? $data['ORDERASSIGNED'] : 'IA.NOT_ASSIGNED';
                $shipTo = $data['SHIPTOCONTACT'];
                foreach ($data['ENTRIES'] as $entry){
                    $printData[$index]['DOCID']=$docID;
                    $printData[$index]['CUSTOMERID']=$customerID;
                    $printData[$index]['ASSIGNEDTO']=$assignedTo;
                    $printData[$index]['SHIPTOCONTACT']=$shipTo;
                    $printData[$index]['ITEMKEY'] = $entry['ITEMID'] ;
                    $printData[$index]['ITEMNAME'] = $entry['ITEMNAME'] ;
                    $printData[$index]['WAREHOUSE']= $entry['WAREHOUSEID'] ;
                    $printData[$index]['QUANTITY'] = $entry['QUANTITY'] ;
                    $printData[$index]['SHIPBYDATE'] = $entry['SHIPBYDATE'];
                    $printData[$index]['ORDERID']= $docID;
                    //Tracking information need to be added for printing
                    if(!empty($entry['TRACKINGENTRIES'])){
                        $printData[$index]['TRACKINGENTRIES']= $entry['TRACKINGENTRIES'];
                    }
                    $index++;
                }
            }
        }
        return $printData;
    }

    /**
     * @param array $xmlData
     * @param string $offline
     *
     * @return bool|string offline returns the output otherwise the output is echoed and a status is returned
     */
    function GeneratePDF($xmlData, $offline = 'false')
    {
        $mytitle = ($this->params['title']) ? $this->CleanTitle($this->params['title']) : 'pdfdownload';

        /** @noinspection PhpUnusedLocalVariableInspection */
        $outPDF = false;
        $outPDFArray = [];

        foreach ($xmlData as $xml ){
            //set startpagenumber value if it is not set already
            if (!isset($this->params['startpagenumber']) || empty($this->params['startpagenumber'])) {
                $this->params['startpagenumber'] = 1;
            }

            if ($this->params['2stage']  && isl_strlen($xml) > Reporter::getCutoffSplitAndJoinThreshold()) {
                //StartTimer('Split and Join');
                $outPDF = $this->splitIAXMLAndJoinPDF($xml);

                $this->params['totalPages'] = $this->GetTotalPageNoFromPDF($outPDF);;
                // Update the startpage number for next iteration
                $this->params['startpagenumber'] += $this->params['totalPages'];
                $outPDFArray[]= $outPDF;

                //StopTimer('Split and Join');
            } else {
                //StartTimer('FO Generation');
                $out_xml = $this->TransformtoXSL($xml, kShowPDF);
                $outPDF = genPDF($out_xml, false, '', '');
                $outPDFArray[]= $outPDF;
            }

        }

        if (empty($outPDFArray)) {
            return false;
        } else {
            $pdfdata = GroupReporter::concatPDFs($outPDFArray, false);
            header("Content-type: application/pdf");
            $ua = UAInfo();
            if ($ua['browser'] == 'IE' && $ua['version.major'] == 11) {
                header("Content-Disposition: attachment; filename=\"$mytitle.pdf\"");
            } else {
                header("Content-Disposition: filename=\"$mytitle.pdf\"");
            }
            header("Content-Length: ".strlen($pdfdata));
            echo $pdfdata;

            return true;
        }
    }


}



