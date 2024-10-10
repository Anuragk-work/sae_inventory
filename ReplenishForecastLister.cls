<?

class ReplenishForecastLister extends NLister
{

    /** @var string $mod */
    var $flds = [];


    /**
     * ReplenishmentLister constructor.
     * @param array $params
     */
    public function __construct($params = [])
    {

        $csvforimport = Request::$r->_export;

        switch ($csvforimport)
        {
            // fields to show when exporting
            case kShowPDF:
            case kShowWord:
            case kShowCSV:
            case kShowExcel:
            $this->flds = [
                'ITEMID',
                'ITEMNAME',
                'NAME',
                'WHENMODIFIED',
                'STATUS',
            ];
            break;

            default:
                // fields to show for lister
                $this->flds = [
                    'ITEMID',
                    'ITEMNAME',
                    'NAME',
                    'WHENMODIFIED',
                    'STATUS',
                    'EXPORT',
                ];
                break;

        }

        $flds =  [
            'ITEMID',
            'ITEMNAME',
            'NAME',
            'WHENMODIFIED',
            'STATUS',

        ];
        $params = INTACCTarray_merge(
            [
                'entity'            => 'replenishforecast',
                'fields' => $flds,
                'helpfile'          => '',
                'title'             => 'IA.REPLENISHMENT_FLUCTUATING_DEMAND_FORECASTS',
                'enablemultidelete' => true,
                'nofilteronthesefields' => [ 'EXPORT' ,'STATUS','WHENMODIFIED'],
                '_customexport' => true,
                'importtype' => 'replenishforecast',
            ]
            , $params
        );

        parent::__construct($params);

        // Overrides for column labels
        $this->addLabelMapping( 'ITEMID', 'IA.ITEM_ID', true);
        $this->addLabelMapping( 'ITEMNAME', 'IA.ITEM_NAME', true);
        $this->addLabelMapping( 'NAME', 'IA.FORECAST_DESCRIPTION', true);
        $this->addLabelMapping( 'WHENMODIFIED', 'IA.LAST_MODIFIED_DATE', true);
        $this->addLabelMapping('STATUS', 'IA.STATUS', true);
        $this->addLabelMapping('EXPORT', 'IA.EXPORT', true);
    }


    /*
     * build a table
     */
    function BuildTable()
    {
        parent::BuildTable();
        $table = &$this->table;

        $op_key = GetOperationId('inv/lists/replenishforecastdetail/edit');
        $entity = 'replenishforecastdetail';
        $sess = null;

        foreach ($this->table as $key => $row)
        {
            $url = "editor.phtml?.action=export&.state=export&.r=" . urlencode($table[$key]['RECORDNO']) . "&item=" . urlencode($table[$key]['ITEMID']) . "&it=$entity&.op=$op_key" . urlencode($sess) . "&" . OptDone(ScriptRequest());;
            $url = "<a href=\"" . $url ."\" ". ">" .GT($this->textMap, 'IA.EXPORT'). "</a>";

            $this->table[$key]['EXPORT'] = $url;

            if (empty($table[$key]['STATUS']))
            {
                // set any empty status values to 'inactive'
                $table[$key]['STATUS'] = GT($this->textMap, 'IA.INACTIVE');
            }
        }
        $this->table = $table;


        $this->SetOutputFields($this->flds, []);

    }

    /**
     * Get raw table data
     *
     * @param array  $querySpec
     * @param string $querytype
     *
     * @return string[][]
     */
    function GetList($querySpec, $querytype = 'normal')
    {

        $res = parent::GetList($querySpec, $querytype);
        return $res;
    }


}


