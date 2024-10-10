<?php

/**
 * Class InvHlthRunLister
 *
 * @author    rpn <ravi@intacct.com>
 * @copyright 2000-2009 Intacct Corporation, All Rights Reserved
 */

/**
 * @category  Cls
 * @package   Source/common
 * @author    rpn <ravi@intacct.com>
 * @copyright 2000-2009 Intacct Corporation, All Rights Reserved
 */

/**
 * Class InvHlthRunLister
 */
class InvHlthRunLister extends NLister
{

    /**
     * @var string $_FPaths
     */
    var $_FPaths = '';

    /**
     * @var string $_FOprs
     */
    var $_FOprs = '';

    /**
     * @var null|string $_FVals
     */
    var $_FVals = '';

    function __construct()
    {
        if (isset(Request::$r->_FTID)) {
            $this->_FPaths = 'TRACKINGID';
            $this->_FOprs = 'eq';
            $this->_FVals = Request::$r->_FTID;
            Request::$r->_FPaths = 'TRACKINGID';
            Request::$r->_FOprs = 'eq';
            Request::$r->_FVals = Request::$r->_FTID;
        }

        parent::__construct(
            array(
                'entity' =>  'invhlthrun',
                'title'	=>  "IA.MAINTAIN_INVENTORY_VALUATION",
                'fields' => array(
                    'WHENCREATED', 'NOTES', 'OBJECT', 'CREATEDBY', 'ERRORDATA', 'DESCRIPTION'
                ),
                'sortcolumn' => 'WHENCREATED:d',
                'helpfile' => '',
                'supressPrivate' => true,
               )
        );
        $this->xssEncode=true;
    }


    /**
     * Figure out if the transaction can be deleted
     *
     * @param int $i the transaction line number
     *
     * @return bool true if the transaction can be deleted else false
     */
    protected function canDelete($i)
    {
        $object = $this->table[$i]['OBJECT'];

        return (($object === I18N::getSingleToken('IA.QUICK_ANALYZED')) ||
            ($object === I18N::getSingleToken('IA.ANALYZED')) ||
            ($object === I18N::getSingleToken('IA.SCHEDULED')));
    }


    /**
     * @param int           $i
     * @param string|null   $owner
     * @param string|null   $ownerloc
     * @param string|null   $ownedObj
     *
     * @return array|string
     */
    function calcDeleteUrl($i, $owner = null, $ownerloc = null, $ownedObj = null) {
        if ($this->canDelete($i)) {
            return parent::calcDeleteUrl($i);
        }
        return array();
    }

    /**
     * Build the query that the base class Lister will use to fetch data to display on this MIV lister
     *
     * @return array the query to be used to fetch data
     */
    function BuildQuerySpec()
    {
        //We store "Schedule" state internally in HLTHRUN table, but tokenized it as "Scheduled" or in French to display. We need
        //to detect the tokenized user input, so we can query with the correct string. Filtering wildcards will not work perfectly
        //in non-English as the comparison below will narrow down the query. For the most part it will work if querying for accurate strings.
        $reset = false;
        $initialStateUserStr = Request::$r->{"F_OBJECT"};
        if (isset($initialStateUserStr) && $initialStateUserStr != '') {
            $stateUserStr = isl_rtrim($initialStateUserStr, '% ');
            $tokens = [ ['id' => 'IA.QUICK_ANALYZED'], ['id' => 'IA.COSTING_UPDATED'], ['id' => 'IA.ANALYZED'], ['id' => 'IA.UPDATED'], ['id' => 'IA.SCHEDULED']];
            $tokensMap = I18N::getTokensForArray($tokens);
            $stateUserStrLen = strlen($stateUserStr);
            if (strncasecmp($stateUserStr, $tokensMap['IA.SCHEDULED'], $stateUserStrLen) === 0) {
                Request::$r->{"F_OBJECT"} = InvHlthRunManager::SCHEDULE;
                $reset = true;
            } else if (strncasecmp($stateUserStr, $tokensMap['IA.ANALYZED'], $stateUserStrLen) === 0) {
                Request::$r->{"F_OBJECT"} = InvHlthRunManager::ThoroughAnalyzed;
                $reset = true;
            } else if (strncasecmp($stateUserStr, $tokensMap['IA.QUICK_ANALYZED'], $stateUserStrLen) === 0) {
                Request::$r->{"F_OBJECT"} = InvHlthRunManager::QuickAnalyzed;
                $reset = true;
            } else if (strncasecmp($stateUserStr, $tokensMap['IA.UPDATED'], $stateUserStrLen) === 0) {
                Request::$r->{"F_OBJECT"} = InvHlthRunManager::ThoroughUpdated;
                $reset = true;
            } else if (strncasecmp($stateUserStr, $tokensMap['IA.COSTING_UPDATED'], $stateUserStrLen) === 0) {
                Request::$r->{"F_OBJECT"} = InvHlthRunManager::QuickUpdated;
                $reset = true;
            }
        }

        $querySpec = parent::BuildQuerySpec();

        //We updated above, we need to put it back so the user input string doesn't change on the UI search box.
        if ($reset) {
            Request::$r->{"F_OBJECT"} = $initialStateUserStr;
        }

        return $querySpec;
    }

    /**
     * Get raw table data
     *
     * @param array  $querySpec
     * @param string $querytype
     *
     * @return string[][]
     */
    function GetList($querySpec, $querytype = 'normal')
    {
        $rtn = parent::GetList($querySpec, $querytype);

        if ( (! Globals::$g->islive) && ($querytype === 'normal') && ($rtn !== false) && (count($rtn) > 0)) {
            // in dev, sometimes someone saves the file with no translation, so lets translate here (shouldn't be needed
            // in production)....
            $search = [
                'IA.COSTING_ISSUES',
                'IA.NEGATIVE_INVENTORY_WARNINGS',
                'IA.NO_OF_NEG_QTY_FOUND',
                'IA.NUMBER_FIXED',
            ];
            $tokens = [];
            foreach ($search as $token) {
                $tokens[] = ['id' => $token];
            }
            I18N::addTokens($tokens);
            $translatedText = I18N::getText();
            $replace = [];
            foreach ($search as $token) {
                $replace[] = GT($translatedText, $token);
            }

            foreach ($rtn as $index => $row) {
                if (isset($row['ERRORDATA'])) {
                    $rtn[$index]['ERRORDATA'] = str_replace($search, $replace, $row['ERRORDATA']);
                }
            }
        }
        if (($rtn !== false) && (count($rtn) > 0)) {
            $tokens = [ ['id' => 'IA.QUICK_ANALYZED'],
                        ['id' => 'IA.COSTING_UPDATED'],
                        ['id' => 'IA.ANALYZED'],
                        ['id' => 'IA.UPDATED'],
                        ['id' => 'IA.SCHEDULED']
                ];
            I18N::getTokensForArray($tokens);

            foreach ($rtn as &$row) {
               InvHlthRunEditor::translateStateValues($row);
            }
            unset($row);
        }
        return $rtn;
    }

}
