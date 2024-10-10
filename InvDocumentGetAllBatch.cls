<?php
/**
 * DDS InvDocumentGetAllBatch
 *
 * @author    Horea Abrudan <habrudan@intacct.com>
 * @copyright 2015  Intacct Corporation, All Rights Reserved
 *
 * This is only needed in order to match the creation pattern in GetListBatchFactory::getGetAllBatch()
 */


/**
 * Class InvDocumentGetAllBatch
 *
 * Required for the GetAllIteratorFactory
 */
class InvDocumentGetAllBatch  extends DocumentBaseBatch
{

    /**
     * set up the doc types
     *
     * @param string    $entity        Name of Entity
     * @param int       $readTimestamp Current time stamp
     * @param int       $pageSize      Page size for data
     * @param array     $params        Query params optional
     */
    public function __construct( $entity, $readTimestamp, $pageSize, $params = array() )
    {
        parent::__construct($entity, $readTimestamp, $pageSize, $params);
    }


}