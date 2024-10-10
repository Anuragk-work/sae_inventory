<?php

/**
 * Class DocumentParamsWizard
 *
 * @author    intacct
 * @copyright 2000-2017 Intacct Corporation
 *
 * This document contains trade secret data that belongs to Intacct
 * Corporation and is protected by the copyright laws.  Information
 * herein may not be used, copied or disclosed in whole or in part
 * without prior written consent from Intacct Corporation.
 */
class DocumentParamsWizard extends Wizard
{

    function __construct()
    {
        parent::__construct(
            [
                'entity' => 'documentparams',
                'title'  => 'IA.DOCUMENT_TEMPLATE_INFORMATION',
                'pages'  => [

                    [
                        'title'  => 'IA.HEADER_INFO',
                        'fields' => [
                            'DOCID',
                            'DOCCLASS',
                            'SALE_PUR_TRANS',
                            'DESCRIPTION',
                            'UPDATES_INV',
                            'UPDATES_GL',
                            'UPDATES_COST',
                            'INVERSE',
                            'UPDATES_PRICELISTID',
                            'TERMS',
                            'CUST_VEND',
                            'EXTERNAL_ISSUE',
                            'PRICELISTID',
                            'RECALLONLY',
                            'EDITABLE_PRICE',
                            'IN_OUT',
                            'SHOW_TOTALS',
                            'FORCE_PRICES',
                            'STATUS',
                        ],
                    ],

                    [
                        'title'  => 'IA.GL_INFORMATION',
                        'fields' => [
                            [
                                'path'    => 'DOCPAR_GL',
                                'title'   => 'IA.GL_INFORMATION',
                                'columns' => [
                                    [ 'path' => 'GLACCOUNT', 'size' => '20' ],
                                    [ 'path' => 'ITEM_GLGROUP', 'size' => '10' ],
                                    [ 'path' => 'ENT_GLGROUP', 'size' => '10' ],
                                    [ 'path' => 'ISOFFSET' ],
                                    [ 'path' => 'DEBIT_CREDIT' ],
                                    [ 'path' => 'MODULE' ],
                                    //array('path' => 'STATUS'),
                                ],
                                '_func'   => 'MultilineLayout',
                            ],
                        ],
                    ],

                    [
                        'title'  => 'IA.TOTALS',
                        'fields' => [
                            [
                                'path'    => 'DOCPAR_TOTALS',
                                'columns' => [
                                    [ 'path' => 'TOTALID', 'size' => '8' ],
                                    [ 'path' => 'Q_QV' ],
                                    [ 'path' => 'SIGN' ],
                                ],
                                '_func'   => 'MultilineLayout',
                            ],
                        ],
                    ],

                    [
                        'title'  => 'IA.SUBTOTALS',
                        'fields' => [
                            [
                                'path'    => 'DOCPAR_SUBTOTAL',
                                'columns' => [
                                    [ 'path' => 'LINENO', 'size' => '8' ],
                                    [ 'path' => 'DISC_CHARGE' ],
                                    [ 'path' => 'DESCRIPTION', 'size' => '30' ],
                                    [ 'path' => 'AMT_PERC', 'size' => '8' ],
                                    [ 'path' => 'VALUE', 'size' => '8' ],
                                    [ 'path' => 'APPORTIONED' ],
                                    [ 'path' => 'GLACCOUNT', 'size' => '20' ],
                                    [ 'path' => 'DEBIT_CREDIT' ],
                                    [ 'path' => 'BASELINE', 'size' => '8' ],
                                    [ 'path' => 'ISTAX' ],
                                    [ 'path' => 'ISAVATAX' ],
                                ],
                                '_func'   => 'MultilineLayout',
                            ],
                        ],

                    ],
                ],
            ]
        );
    }
}


