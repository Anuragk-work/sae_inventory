<?php
/**
 * DDS InvDocumentGetUpdatedIterator
 *
 * @author    Horea Abrudan <habrudan@intacct.com>
 * @copyright 2015  Intacct Corporation, All Rights Reserved
 *
 * This is only needed in order to match the creation pattern in GetListIteratorFactory::getGetUpdatedIterator()
 */

/**
 * Class InvDocumentGetUpdatedIterator
 */
class InvDocumentGetUpdatedIterator  extends DocumentGetUpdatedIterator
{

    /**
     * @param EntityManager $entMgr      Current EntityManger class
     * @param GetListBatch  $batch       The current batch
     * @param array         $queryParams The query parameters
     */
    public function __construct(EntityManager $entMgr, GetListBatch $batch, $queryParams)
    {
        parent::__construct($entMgr, $batch, $queryParams);
    }


}