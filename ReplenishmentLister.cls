<?

class ReplenishmentLister extends NLister
{

    /**
     * ReplenishmentLister constructor.
     */
    public function __construct()
    {
        parent::__construct(
            [
                'entity'            => 'replenishment',
                'fields'            => [ 'SNAPSHOT_NAME', 'TRANSACTION_DEFINITION', 'TRANSACTION_DATE',
                                         'FILTER_ASOFDATE',
                                         'FILTER_VENDORID', 'FILTER_WAREHOUSE', 'CREATEDBY_USERID' ],
                'helpfile'          => '',
                'title'             => 'IA.REPLENISHMENT_SNAPSHOTS',
                'enablemultidelete' => true,
                'disableadd'        => true,
            ]
        );
    }

    /**
     * @param int   $i
     * @param array $vals
     *
     * @return array
     */
    function calcEditUrlParms($i, $vals)
    {
        return []; // parent::calcEditUrlParms($i, $vals);
    }

    /**
     * @param int   $i
     * @param array $vals
     *
     * @return array
     */
    function calcViewUrlParms($i, $vals)
    {
        return []; // parent::calcViewUrlParms($i,$vals);
    }

}


