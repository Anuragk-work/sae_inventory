<?php
/**
 * AllowedOperationsHandler
 *
 * @author    Shreerajath Hebbar
 * @copyright Copyright (C)2023 Sage Intacct Corporation, All Rights Reserved
 *
 */
class DocumentParamsAllowedOperationsHandler extends AllowedOperationsHandler
{
    const NO_CHANGE = "No Change";
    const FALSE = "false";
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
    protected function getMenuEntry(): string
    {
        return AllowedOperations::ENTRY_ACTIVITIES;
    }

    /**
     * @return array
     */
    protected function getOperations(): array

    {
        $operations = parent::getOperations();
        return array_merge($operations, ['showRecurringTemplates']);
    }

    /**
     * @param array $record
     * @param string|null $moduleKey
     * @return bool
     */
    protected function showRecurringTemplates(array $record, /** @noinspection PhpUnusedParameterInspection */ string $moduleKey = null): bool
    {
        return false;
    }

    /**
     * @param array $record
     * @param string $entity
     * @return bool
     */
    protected function calcRecurringTemplates(array $record, string $entity): bool
    {
        $userid = Globals::$g->_userid;;
        list($user,$cny) = explode('@', $userid);
        $docparMgr = Globals::$g->gManagerFactory->getManager($entity);
        $args = array($record['DOCID'], $user, $cny, $cny );
        $res = $docparMgr->DoQuery('QRY_DOCUMENTPARAMS_GET_USER_PERMISSION', $args);
        if(
            (($res[0]['USERPERM'] ?? 'F') =='T' && ($res[0]['PERM'] ?? '?') == 'D')
            || in_array($record['DOCID'], DocumentParamsManager::$systemGeneratedTDs)
        ) {
            //if user is denied perm for this TD
            return false;
        } else {
            $docpar['CREATION_RULE'] = $docparMgr->getCreationRule($record);
            if (!('T' === $docpar['CREATION_RULE'])) {
                return false;
            }
        }

        $noChangeTokenVal =self::NO_CHANGE;
        $enabledDocChange = isNullOrBlank($record['ENABLEDOCCHANGE']) ? $noChangeTokenVal : I18N::getSingleToken($record['ENABLEDOCCHANGE']);
        if($enabledDocChange != $noChangeTokenVal){
            return false;
        }

        $falseVal =  self::FALSE;
        $enableContractBilling = isNullOrBlank($record['ENABLECONTRACTBILLING']) ? $falseVal : I18N::getSingleToken($record['ENABLECONTRACTBILLING']);
        if($enableContractBilling != $falseVal){
            return false;
        }

        return true;
    }

    /**
     * @return array
     */
    protected function getFieldsForPermissionChecks() : array
    {
        $fields = parent::getFieldsForPermissionChecks();
        $fields = array_merge($fields, [ 'DOCID', 'ENABLEDOCCHANGE', 'TD_CREATION_RULE']);
        return $fields;
    }
}
