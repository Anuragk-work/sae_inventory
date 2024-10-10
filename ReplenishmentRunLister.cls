<?php
/**
 * File ReplenishmentRunLister.cls contains the class ReplenishmentRunLister
 *
 * @author
 * @copyright 2000-2018 Intacct Corporation
 *
 * This document contains trade secret data that belongs to Intacct
 * Corporation and is protected by the copyright laws.  Information
 * herein may not be used, copied or disclosed in whole or in part
 * without prior written consent from Intacct Corporation.
 */

/**
 * Replenishment run
 *
 * Class ReplenishmentRunLister
 */
class ReplenishmentRunLister extends NLister
{
    public function __construct()
    {
        $fields = [
            'RECORDNO',
            'WHENCREATED',
            'TRANSACTION_DEFINITION',
            'TRANSACTION_DATE',
            'RUN_BY',
            'STATE',
            'EXECUTOION_MODE',
        ];

        parent::__construct(
            [
                'entity'            => 'replenishmentrun',
                'fields'            => $fields,
                'sortcolumn'        => 'WHENCREATED:d',
                'disableadd'        => true,
                'disabledelete'     => true,
                'importtype'        => '',
                'enablemultidelete' => false,
                'entitynostatus'    => true,
                'helpfile'          => '',
            ]
        );
    }
}