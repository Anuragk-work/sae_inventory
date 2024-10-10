<?  
/**
 * Lister class for Warehouse transfer 
 * 
 * @author    Senthil <skumar@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

/**
 * Lister class for the Warehouse transfer 
 */
class ICTransferLister extends NLister
{

    public function __construct()
    {
        $params = array(
            'entity' => 'ictransfer',
            'importtype' => 'ictransfer',
            'importperm' => 'inv/lists/ictransfer/create',
            'fields' => array(
                'DOCNO', 'TRANSACTIONDATE', 'DESCRIPTION', 'REFERENCENO', 'TRANSFERTYPE', 'TRANSFERSTATE'
            ),
            'sortcolumn'    => 'TRANSACTIONDATE:d, DOCNO:d',
            'helpfile' => '',
            'enablemultidelete' => true,
            'enabledrafteditdelete' => true,
        );

        parent::__construct($params);
    }
    
        /**
     * Hook function to override STATE column alias
     *
     * @return string
     */
    public function getStateColumnAlias()
    {
        return 'TRANSFERSTATE';
    }
    
        /**
     * Hook function to override 'Draft' state value used to render Edit link for draft entries
     *
     * @return string
     */
    public function getDraftStateValue()
    {
        return 'D';
    }
    
}