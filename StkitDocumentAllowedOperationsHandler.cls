<?php
/**
 * AllowedOperationsHandler
 *
 * @author    Ravindra Kumar
 * @copyright Copyright (C)2024 Sage Intacct Corporation, All Rights Reserved
 *
 */

class StkitDocumentAllowedOperationsHandler extends AllowedOperationsHandler
{
    /**
     * @inheritDoc
     */
    public function __construct(EntityManager $entManager)
    {
         parent::__construct($entManager);
    }


    /**
     * @inheritDoc
     */
     protected function getOperations() : array
     {
         $operations = parent::getOperations();
         $operations = array_merge($operations, ['canDisassemble']);

         return $operations;
     }

    /**
     * @return bool
     */
    protected function canDisassemble(array $record, string $moduleKey = null): bool
    {
        if (isset($record['DOCPARID']) && $record['DOCPARID'] === StkitDocumentManager::BUILDKIT) {
            return $record['STATE'] !== DocumentManager::DRAFT_STATE && $record['STATE'] !== 'Converted';
        }
        return false;
    }

    /**
     * Record Level Check for Edit Operation
     *
     * @param array $record
     *
     * @return bool
     */
    protected function canEdit(array $record) : bool {
        return ($record['STATE'] == DocumentManager::DRAFT_STATE) && $this->isAllowedOperation('canEdit', 'inv');
    }

    /**
     * @inheritDoc
     */
    protected function getFieldsForPermissionChecks() : array
    {
        $fields = parent::getFieldsForPermissionChecks();
        $fields = array_merge($fields, ['STATE'], ['DOCPARID']);

        return $fields;
    }

}