<?

/**
 * Class InvDocumentParEntityPropManager
 *
 * Class implementing "manager" behavior for transaction definition
 * properties specific for a given entity. Represents the single line item
 * in the TD's Entities tab.
 *
 * @author    Samvel Mirijanyan <smirijanyan@intacct.com>
 * @copyright 2000-2015 Intacct Corporation All, Rights Reserved
 */
class InvDocumentParEntityPropManager extends DocumentParEntityPropManager {

    /**
     * @param string        $id
     * @param array|null    $fields
     *
     * @return array|bool
     */
    public function Get($id, $fields=null)
    {
        $values = parent::Get($id,$fields);
        if (is_array($values)) {
            // when system created XSL is assigned to docpar the entity file is not populating the XSLTEMPLATEDESCRIPTION
            // so getting Description (i.e. template name) from XSLTEMPLATE and populating XSLTEMPLATEDESCRIPTION
            if (isset($values['XSLTEMPLATE']) && (!isset($values['XSLTEMPLATEDESCRIPTION']) || $values['XSLTEMPLATEDESCRIPTION'] == '' )) {
                $XslformatMgr = Globals::$g->gManagerFactory->getManager('xslformat');
                $formatdata = $XslformatMgr->DoQuery('QRY_XSLFORMAT_SELECT_RAW_FROM_RECORDNO', array($values['XSLTEMPLATE'], $this->_cny));
                $values['XSLTEMPLATEDESCRIPTION'] = $formatdata[0]['DESCRIPTION'];
            }
        }
        return $values;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values) {
        $this->prepXslTemplateId($values);
        return parent::regularAdd($values);
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularSet(&$values) {
        $this->prepXslTemplateId($values);
        return parent::regularSet($values);
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
     * @param $values
     * @return void
     */
    protected function prepXslTemplateId(&$values){
        // For REST API sometimes user can mention XSLTEMPLATEDESCRIPTION that is Template ID
        // so populating XSLTEMPLATE with XSLTEMPLATEDESCRIPTION
        if (isset($values['XSLTEMPLATEDESCRIPTION']) && $values['XSLTEMPLATEDESCRIPTION'] != '') {
            $values['XSLTEMPLATE'] = $values['XSLTEMPLATEDESCRIPTION'];
        }
    }


    /**
     * @param array $values
     *
     * @return mixed|null
     */
    protected function getXSLTemplateRecordNo($values)
    {
        $recordno = null;
        if (isset($values['XSLTEMPLATE']) && $values['XSLTEMPLATE'] !== '') {
            $docParResult = EntityManager::GetListQuick('invdocumentparams', ['DOCCLASS'],
                ['RECORDNO' => $values['DOCPARNO']]);
            $docClass = '';
            if (is_array($docParResult) && isset($docParResult[0])) {
                $docClass = $docParResult[0]['DOCCLASS'];
            }
            $xslformatMgr = Globals::$g->gManagerFactory->getManager('xslformat');
            $params = [
                'selects' => ['RECORDNO'],
                'filters' => [
                    [
                        ['DESCRIPTION', '=', $values['XSLTEMPLATE']],
                        ['MODULEID', '=', '7.INV'],
                        ['DOCTYPE', '=', $docClass],
                    ],
                ],
            ];
            $result = $xslformatMgr->GetList($params);

            if (is_array($result) && isset($result[0]) && $result[0]['RECORDNO'] != '') {
                $recordno = $result[0]['RECORDNO'];
            } else {
                $params = [
                    'selects' => ['RECORDNO'],
                    'filters' => [
                        [
                            ['RECORDNO', '=', $values['XSLTEMPLATE']],
                            ['MODULEID', '=', '7.INV'],
                            ['DOCTYPE', '=', $docClass],
                        ],
                    ],
                ];
                $result = $xslformatMgr->GetList($params);
                if (is_array($result) && isset($result[0]) && $result[0]['RECORDNO'] != '') {
                    $recordno = $result[0]['RECORDNO'];
                }

            }
        }

        return $recordno;
    }

}