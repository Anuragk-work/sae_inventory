0<?php
/**
 * DDS InvDocumentGetUpdatedBatch
 *
 * @author    Horea Abrudan <habrudan@intacct.com>
 * @copyright 2015  Intacct Corporation, All Rights Reserved
 *
 * This is only needed in order to match the creation pattern in GetListBatchFactory::getGetUpdatedBatch()
 */


/**
 * Class InvDocumentGetUpdatedBatch
 */
class InvDocumentGetUpdatedBatch extends DocumentGetUpdatedBatch
{

    /**
     * @param string $entity        Entity Name
     * @param string $timestampGMT  Provided timestamp GMT for change detection
     * @param int    $readTimestamp Current timestamp
     * @param int    $pageSize      Data page size
     * @param array  $params        Query parameters optional
     */
    function __construct($entity, $timestampGMT, $readTimestamp, $pageSize, $params = array())
    {
        parent::__construct($entity, $timestampGMT, $readTimestamp, $pageSize, $params);
    }

}