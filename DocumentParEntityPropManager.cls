<?

/**
 * Class DocumentParEntityPropManager
 *
 * Class implementing common "manager" behavior for all types of TDs for
 * properties specific for a given entity. Represents the single line item
 * in the TD's Entities tab.
 *
 * @author    Samvel Mirijanyan <smirijanyan@intacct.com>
 * @copyright 2000-2015 Intacct Corporation All, Rights Reserved
 */
class DocumentParEntityPropManager  extends OwnedObjectManager {

    /**
     * @param string   $id
     * @param string[] $fields
     *
     * @return array|false
     */
    public function Get($id, $fields=null)
    {
        return parent::get($id);
    }

    /**
     * Returns number of entities assigned an entity specific properties
     * for a given transaction definition.
     *
     * @param string $docparkey     RECORDNO (record#) of the TD
     *
     * @return int
     */
    public function getEntityCountWithProperties($docparkey)
    {
        $filters = [
            [
                ['DOCPARNO', '=', $docparkey],
            ]
        ];
        $result = $this->GetCount(['filters' => $filters]);

        return $result;
    }

    /**
     * Returns entity specific properties for the given transaction definition.
     *
     * @param string $docid
     * @param string $locationId
     *
     * @return array|false|null
     */
    public function getEntityProperties($docid, $locationId)
    {
        $recordNo = null;
        $entityProps = null;
        $keyFieldName = 'RECORDNO';
        $filters = [
            [
                ['DOCPARNO', '=', $docid],
                ['ENTITYNO', '=', $locationId]
            ]
        ];

        $list = $this->GetList(
            array(
                'selects' => array($keyFieldName),
                'filters' => $filters)
        );
        if ($list && is_array($list[0])) {
            $recordNo = $list[0][$keyFieldName];
        }

        if (isset($recordNo)) {
            $entityProps = $this->Get($recordNo);
        }

        return $entityProps;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values) {
        global $gErr;

        $source = "DocumentParEntityProp::Add";

        $ok = $this->_QM->beginTrx($source);

        $nextId = $this->GetNextRecordKey();
        $ok = $ok && isset($nextId);

        $values[':record#'] = $nextId;
        $values['RECORDNO'] = $nextId;

        $ok = $ok && $this->prepareEntityValues($values);

        // Call validation here

        $ok = $ok && parent::regularAdd($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Error creating TD entity property record!";
            $gErr->addIAError('INV-0375', __FILE__ . ':' . __LINE__, $msg, []);
            epp("$source: Error: $msg");
            $this->_QM->rollbackTrx($source);
        }

        return $ok;

    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularSet(&$values) {
        $ok = $this->prepareEntityValues($values);
        $ok = $ok && parent::regularSet($values);
        return $ok;
    }

    /** @noinspection PhpUnusedPrivateMethodInspection
     * 
     *  Sets the values for enabling numbering scheme and preserving
     * sequence number depending of value provided / not provided
     * for the numbering sequence.
     *
     * @param  array $values
     */
    private function prepareNumberingScheme(&$values)
    {
        if (isArrayValueProvided($values, 'SEQUENCE')) {
            $values['ENABLE_SEQNUM'] = 'true';
        } else {
            $values['ENABLE_SEQNUM'] = 'false';
            $values['PRESERVE_SEQNUM'] = 'false';
        }
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    private function prepareEntityValues(&$values)
    {
        global $gErr;
        global $gManagerFactory;
        $ok = true;

        $values[':entitykey'] = '';
        if (isArrayValueProvided($values, 'ENTITY_NAME')) {
            $locManager = $gManagerFactory->getManager('location');
            $loc = explode('--', $values['ENTITY_NAME']);
            $loc = array_shift($loc);
            $recordno = $locManager->GetRecordNoFromVid($loc);
            if (isset($recordno)) {
                $values[':entitykey'] = $recordno;
            } else {
                $gErr->addIAError(
                    'INV-0376', __FILE__ . ':' . __LINE__,
                    "Incorrect value provided for the Entity Location: " . $values['ENTITY_NAME'],
                    ['VALUES_ENTITY_NAME' => $values['ENTITY_NAME']]
                );
                $ok = false;
            }
        }

        // If the sequence (numbering pattern) is provided (text in a free form) check
        // for a proper record in the database and populate the default
        if ($ok) {
            $values[':seqnumkey'] = '';
            if (isArrayValueProvided($values, 'SEQUENCE')) {
                $seqnumManager = $gManagerFactory->getManager('seqnum');
                $recordno = $seqnumManager->GetRecordNoFromVid($values['SEQUENCE']);
                if (isset($recordno)) {
                    $values[':seqnumkey'] = $recordno;
                } else {
                    $gErr->addIAError(
                        'INV-0377', __FILE__ . ':' . __LINE__,
                        "Incorrect value provided for the Numbering Scheme: " . $values['SEQUENCE'],
                        ['VALUES_SEQUENCE' => $values['SEQUENCE']]
                    );
                    $ok = false;
                }
            }
        }

        // If the Printed Format  is provided (text in a free form) check
        // for a proper record in the database and populate the default
        if ($ok) {
            $values[':docxslkey'] = '';
            if ($values['XSLTEMPLATE']) {
                $recordno = $this->getXSLTemplateRecordNo($values);
                if (isset($recordno)) {
                    $values[':docxslkey'] = $recordno;
                } else {
                    // Note: in some places, the XSLTEMPLATE is the RECORD# itself....
                    //    why do we overload the name?  Crazy!
                    $recordno   = $values['XSLTEMPLATE'];
                    $xslformatMgr = Globals::$g->gManagerFactory->getManager('xslformat');
                    $formatdata = $xslformatMgr->DoQuery('QRY_XSLFORMAT_SELECT_RAW_FROM_RECORDNO', array($recordno), GetMyCompany());
                    if ( ! isset($formatdata[0]['XSL'])) {
                        $gErr->addIAError(
                            'INV-0378', __FILE__ . ':' . __LINE__,
                            "Incorrect value provided for the Printed Format: " . $recordno,
                            ['RECORDNO' => $recordno]
                        );
                        $ok = false;
                    }
                }
            }
        }


        // If the subtotal template is provided populate the record# field
        $values['SUBTOTALTEMPLATEKEY'] = null;
        if ($ok && isset($values['SUBTOTALTEMPLATE']) &&  $values['SUBTOTALTEMPLATE'] != '') {
            $subtotaltemplateMgr = null;

            if ($this instanceof PODocumentParEntityPropManager) {
                $subtotaltemplateMgr = $gManagerFactory->getManager('posubtotaltemplate');
            } else if ($this instanceof SODocumentParEntityPropManager) {
                $subtotaltemplateMgr = $gManagerFactory->getManager('sosubtotaltemplate');
            } else {
                $gErr->addIAError(
                    'INV-0103', __FILE__ . ':' . __LINE__,
                    "Subtotal Templates are only supported in Order Entry and Purchasing modules.", []);
                $ok = false;
            }

            if ($ok && isset($subtotaltemplateMgr) ) {
                // read top level entity subtotalDetail
                $template = $subtotaltemplateMgr->get($values['SUBTOTALTEMPLATE']);

                if ( $template && isset($template['RECORDNO']) ) {
                    $values['SUBTOTALTEMPLATEKEY'] = $template['RECORDNO'];
                } else {
                    $gErr->addIAError('INV-0379', __FILE__ . ':' . __LINE__,
                        "Incorrect value provided for the Subtotal Template: " . $values['SUBTOTALTEMPLATE'],
                        ['VALUES_SUBTOTALTEMPLATE' => $values['SUBTOTALTEMPLATE']]
                    );
                    $ok = false;
                }
            }

        }

        return $ok;
    }

    /**
     * @param int|string $ID
     *
     * @return bool
     */
    public function Delete($ID) {
        return parent::Delete($ID);
    }

    /**
     * @param array $values
     *
     * @return int|null
     */
    protected function getXSLTemplateRecordNo($values)
    {
        $xslformatMgr = Globals::$g->gManagerFactory->getManager('xslformat');

        return $xslformatMgr->GetRecordNo('DESCRIPTION', $values['XSLTEMPLATE']);
    }

}