<?php
/**
 * class DocumentLister extends NLister
 */
import('DocumentLister');
class InvDocumentLister extends DocumentLister
{

    function __construct()
    {
        $this->mod = 'inv';

        $dt = Request::$r->_dt;
        $batchtitle = Request::$r->_batchtitle;

        if (isset($batchtitle) && $batchtitle != ''){
            $title = [
                'id' =>  "IA.INVENTORY_BATCH_TITLE", 'placeHolders' => [['name' => 'BATCH_TITLE' , 'value' => $batchtitle]]
            ];
        }else if(is_null($dt)){
            $title = "IA.INVENTORY_CONTROL_TRANSACTIONS";
        }else{
            $title = [
                'id' => "IA.INVENTORY_CONTROL_TRANSACTIONS_DOC_TYPE", 'placeHolders' => [[ 'name' =>'DOC_TYPE' ,  'value' =>  util_encode($dt)]]
            ];
        }

        if (isset($batchtitle)) {

            $bmenu = array(
                "'CONVERT'",
                'DOCPARID',
                'DOCNO',
                'PONUMBER',
                'WHENCREATED',
                'STATE',
                "'URL'",
            );
        } else {
            $bmenu = array(
                "'CONVERT'",
                'DOCPARID',
                'DOCNO',
                'PONUMBER',
                'INVBATCH',
                'WHENCREATED',
                'STATE',
                "'URL'",
            );
        }
        $params = array(
            'entity' => 'invdocument',
            'importtype' => 'invdocument',
            'importperm' => 'inv/lists/invdocument/create',
            'title' => $title,
            'fields' => $bmenu,
            'sortcolumn' => 'WHENCREATED:d, DOCNO:d',
            'helpfile' => 'Viewing_and_Managing_the_Inventory_Documents_List',
            'defaultview' => 'Recently viewed',
            'enablemultidelete' => true,
        );

        if ($dt) {
            $this->GetEditDeletePolicy($dt);
            if ($this->_deletePolicy == 'N') {
                $params['disabledelete'] = 1;
                unset($params['enablemultidelete']);
            }

            //We don't allow add button on supplies issue/return documents
            if ($dt === PODocumentManager::SUPPLIESISSUEDOCTYPE
                || $dt === PODocumentManager::SUPPLIESRETURNDOCTYPE) {
                $params['disableadd'] = true;
            }

            //Edit is set in CalcEditUrl in parent class
        } else {
            //No add link in common lister
            $params['disableadd'] = true;
        }

        parent::__construct($params);
    }

    /**
     * @param array  $record
     * @param int    $contextLocation
     * @param string $owner
     * @param string $ownerloc
     *
     * @return string
     */
    protected function getConvertURL($record, $contextLocation, $owner, $ownerloc)
    {
        if ($record['ADJ'] == 'true') {
            return '';
        }
        
        return parent::getConvertURL($record, $contextLocation, $owner, $ownerloc);
        
    }
    
    //	This method overrides the base function and adds a query filter to the array.
    //  this filters rows which have glentrykey as current glkey from url.
    /**
     * @return array
     */
    function BuildQuerySpec()
    {
        $queryStr = parent::BuildQuerySpec();
        $queryStr['selects'][] = 'ADJ';
        $batch = Request::$r->_batch;
        if( !empty($batch) ) {
            $fltrs = array('INVBATCHKEY','=',"$batch");
            if( !empty($queryStr['filters'][0]) ) {
                $queryStr['filters'][0][] = $fltrs;
            }
            else{
                $queryStr['filters'][0][0]  = $fltrs;
            }
        }
        return $queryStr;
    }

    /**
     * @return string
     */
    function genGlobs()
    {
        $batch = Request::$r->_batch;
        $ret = parent::genGlobs();
        if( !empty($batch) ) {
            $batchtitle = Request::$r->_batchtitle;
            $ret .= "<g name='.batch'>" . $batch . "</g>";
            $ret .= "<g name='.batchtitle'>" . URLCleanParams::insert('.batchtitle', $batchtitle) . "</g>";
        }
        return $ret;
    }
}

