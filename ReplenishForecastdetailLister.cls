<?

class ReplenishForecastDetailLister extends NLister
{

    /**
     * ReplenishmentLister constructor.
     * @param array $params
     */
    public function __construct($params = [])
    {
        $flds =  [
            'RECORDNO',
            'ITEMID',
            'NAME',
            'WHENCREATED',
            'WHENMODIFIED',
            'CREATEDBY',
            'MODIFIEDBY',
            'ITEMNAME',
            'STATUS',
            'ITEM_UOM' ,

        ];


        $params = INTACCTarray_merge(
            [
                'entity'            => 'ReplenishForecastDetail',
                'fields' =>  $flds,
                'helpfile'          => '',
                'title'             => 'IA.REPLENISHMENT_FLUCTUATING_DEMAND_FORECASTS',
//                'enablemultidelete' => true,
//                'nofilteronthesefields' => [ 'EXPORT' ,'STATUS','WHENMODIFIED'],
                '_nocount' => true,
            ]

            , $params
        );

        parent::__construct($params);
    }

//
//    /*
//     * build a table
//     */
//    function BuildTable()
//    {
//        parent::BuildTable();
////        $table = &$this->table;
////        foreach ($this->table as $key => $row)
////        {
//////            $this->table[$key]['EXPORT']
//////                = "<a href=\"#\" onclick=\" exportfunction(" . $row['RECORDNO'] . ");\" " . ">Export</a>";
////
////            if (empty($table[$key]['STATUS']))
////            {
////                // set any empty status values to 'inactive'
////                $table[$key]['STATUS'] = 'Inactive';
////            }
////        }
////        $this->table = $table;
////
////        $flds = [
////            'ITEMID',
////            'ITEMNAME',
////            'NAME',
////            'WHENMODIFIED',
////            'STATUS',
//////            'EXPORT',
////        ];
////
////        $lbls = [
//////            'RECORDNO',
////            'Item ID',
////            'Item name',
////            'Forecast description',
////            'Last modified date',
////            'Forecast status',
//////            'Export',
////        ];
////
////
////        $this->SetOutputFields($flds, $lbls);
//    }
//
//    function GetList($querySpec, $querytype = 'normal')
//    {
//
//        $res = parent::GetList($querySpec, $querytype);
//        return $res;
//    }
//
////DrawHTML()
//
//    function DrawHTML()
//    {
//
//        $table = &$this->table;
//
////        $gManagerFactory = Globals::$g->gManagerFactory;
////        $ReplenishForecastDetailMgr = $gManagerFactory->getManager('ReplenishForecastDetail');
////
////        $ReplenishForecastDetailLister = Lister::GetEntityLister('ReplenishForecastDetail');
////
////
////        $items = [];
////        foreach ($table as $item)
////        {
////    $items[] = $item['ITEMID'];
////
////        }
////
////        $filtertemplate = [
////            'filters' => [],
////            'orders'  => [],
////        ];
////
////            $filtertemplate['filters'][0][] = ['ITEMID', 'IN', $items];
//////        $result = $ReplenishForecastDetailMgr->GetList($filtertemplate);
////
////
////        $result = $ReplenishForecastDetailLister->GetList($filtertemplate);
////        $ReplenishForecastDetailLister->DrawHTML();
//
//
//
////        $this->table = $result;
//
//        parent::DrawHTML();
//
//    }
//
//    function GenerateOutput($xml, $type)
//    {
//        switch ($type) {
////            case kShowHTML:
////                $ok = $this->toHTML($xml);
////                break;
//            case kShowPDF:
//                $ok = $this->toPDF($xml);
//                break;
////            case kShowRTF:
////                //TODO: obsolete?
////                dieFL("Convert to RTF is unsupported");
////                $ok = false;
////                break;
////            case kShowPDFForm:
////                //TODO: obsolete?
////                dieFL("Convert to PDF form is unsupported");
////                $ok = false;
////                break;
////            case kShowText:
////                //TODO: obsolete?
////                dieFL("Convert to Text is unsupported");
////                $ok = false;
////                break;
//            case kShowCSV:
//            case kShowCSVImport:
//                $ok = $this->toCSV($xml);
//                break;
//            case kShowExcel:
//                $ok = $this->toExcel($xml);
//                break;
//            case kShowWord:
//                $ok = $this->toWord($xml);
//                break;
////            case kShowDataXML:
////            case kShowIntacctXML:
////                $ok = $this->toOutputXML($xml);
////                break;
////            case kShowFO:
////                dieFL("Convert to FO is unsupported");
////                $ok = false;
////                break;
////            case kXSDExport:
////                dieFL("Convert to XSD export is unsupported");
////                $ok = false;
////                break;
////            case kXMLExport:
////                dieFL("Convert to XML export is unsupported");
////                $ok = false;
////                break;
////            case  kShowFlash:
////                dieFL("Convert to Flash is unsupported");
////                $ok = false;
////                break;
////            case  kShowGraph:
////                dieFL("Convert to Graph is unsupported");
////                $ok = false;
////                break;
////            default:
////                dieFL("Convert to HTML is unsupported");
////                $ok = false;
////                break;
//        }
//
//        return $ok;
//    }

}


