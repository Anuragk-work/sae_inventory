<?php
/**
 * DDS InvDocumentGetCreatedIterator
 *
 * @author    Horea Abrudan <habrudan@intacct.com>
 * @copyright 2015  Intacct Corporation, All Rights Reserved
 *
 * This is only needed in order to match the creation pattern in GetListIteratorFactory::getGetCreatedIterator()
 */


/**
 * Class InvDocumentGetCreatedIterator
 *
 * This is only needed in order to match the creation pattern in GetListIteratorFactory::getGetCreatedIterator()
 */
class InvDocumentGetCreatedIterator  extends DocumentGetCreatedIterator
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