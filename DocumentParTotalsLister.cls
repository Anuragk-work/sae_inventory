<?

/**
 * Class DocumentParTotalsLister
 */
class DocumentParTotalsLister extends NLister
{

    function __construct()
    {
        parent::__construct(
            array (
            'entity'        =>  'documentpartotals',
            'fields'        =>  array(
            'RECORDNO',
            'DOCID',
            'Q_QV',
            'TOTALID',
            'SIGN'
            ),
            'title'         => 'IA.INVENTORY_TOTALS',
            'helpfile'      => 'Locations_Lister'
            )
        );
    }    
}