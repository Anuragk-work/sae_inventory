<?php

//=============================================================================
//
//	FILE:		DataRetrieverTester.cls
//	AUTHOR:		Odysseas
//
//=============================================================================



import('EntityDataRetriever');
import('EntityManager');
import('ManagerFactory');
import('UOMManager');


//InitGlobals();
class UOMManagerTester extends TestCase
{
    /**
     * @var UOMManager $uomMgr
     */
    private $_UOMMgr;

    /**
     * @var array $_infoMap
     */
    private $_infoMap;

    /**
     * @var string $_idPrefix
     */
    private $_idPrefix = 'TEST-1973';

    /**
     * @var string $_cny
     */
    private $_cny;

    /**
     * @param string $_name
     */
    public function __construct($_name)
    {
        parent::__construct($_name);
    }

    /**
     *
     */
    public function Setup()
    {
        //global $_userid;
        //i,ii,ii at inv database
        //$_userid='2@1683@A';
        global $gManagerFactory;
        $this->_cny = '1683';

        Sudo('2@'.$this->_cny.'@A', 'prod_owner_02/prodowner2001@dev02');
        parent::setUp();

        $this->_UOMMgr = $gManagerFactory->getManager('uom');
        $this->_infoMap =& $this->_UOMMgr->GetEntityInfoMap();

    }

    /**
     *
     */
    public function TearDown()
    {
        ExecSimpleStmt("DELETE FROM icuom WHERE unit like '".$this->_idPrefix."%'  AND cny# =".$this->_cny);
    }

    /**
     * @param string $fld
     *
     * @return string
     */
    public function GetMaxLengthInputValue($fld)
    {
        epp("GetMaxLengthInputValue($fld)");
        $testVals = array (
        'integer'    =>    9,
        'decimal'    =>    9,
        'text'        =>    'Z',
        );
        $max    = $this->_infoMap[$fld]['type']['maxlength'];
        $type    = $this->_infoMap[$fld]['type']['ptype'];
        $value = str_repeat($testVals[$type], $max); 
        epp("returning $value");
        return $value;
    }

    /**
     *
     */
    public function testGet_p()
    {
        epp("BEGIN testGet_p");

        $items = DOM::CreateFromString(
            '
<record-list>
	<record>
		<UNIT>'.$this->_idPrefix.'-0</UNIT>
		<NUMDECIMALS>1</NUMDECIMALS>
	</record>
	<record>
		<UNIT>'.$this->_idPrefix.'-1</UNIT>
		<NUMDECIMALS>'.$this->GetMaxLengthInputValue('NUMDECIMALS').'</NUMDECIMALS>
	</record>
</record-list>
'
        );

        foreach ($items->ToSimplePHP() as $item) {
            $ok = $this->_UOMMgr->add($item);
            if (!$ok) {
                epp("UOMManagerTester::testGet : Add failed");
                eppp($item);
            }
        }

        /**
         * @var bool|DOM|DataRetriever $dr
         */
        $dr = GetDataRetriever(
            DOM::CreateFromString(
                '
<data-retriever id="1" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<connection type="entity" entity="UOM"/>
    <column-list> 
		<column name="UNIT" seq="1" />
		<column name="NUMDECIMALS" seq="2" />
	</column-list>
	<filter-list>
		<filter attr="UNIT" op="like" value="'.$this->_idPrefix.'%" seq="1"/>
	</filter-list>
</data-retriever>
		'
            )
        );

        $dr->Bind();

        $result = $dr->FetchAllXML();
        $this->assert(
            is_object($result) && $result->Equals($items), 
            'Returned record did not match original.'
        );
        ExecSimpleStmt("DELETE FROM icuom WHERE unit like '".$this->_idPrefix."%'  AND cny# =".$this->_cny);
        epp("END testGet_p");
    }

    /**
     *
     */
    public function testSet_p()
    {
        epp("BEGIN testSet_p");
        $source = "UOMManagerTester::testSet";

        $items = DOM::CreateFromString(
            '
<record-list>
	<record>
		<UNIT>'.$this->_idPrefix.'</UNIT>
		<NUMDECIMALS>1</NUMDECIMALS>
	</record>
</record-list>
'
        );
        $rhashes = array();
        foreach ($items->ToSimplePHP() as $item) {
            $ok = $this->_UOMMgr->add($item);
            $rhashes[] = $item['RECORDNO'];
            if (!$ok) {
                epp("UOMManagerTester::testGet : Add failed");
                eppp($item);
            }
        }

        // this rhashes thing works since there is only one.
        $new_items = DOM::CreateFromString(
            '
<record-list>
	<record>
		<RECORDNO>'.$rhashes[0].'</RECORDNO>
		<UNIT>'.$this->_idPrefix.'</UNIT>
		<NUMDECIMALS>2</NUMDECIMALS>
	</record>
</record-list>
'
        );
        $expected_items = DOM::CreateFromString(
            '
<record-list>
	<record>
		<UNIT>'.$this->_idPrefix.'</UNIT>
		<NUMDECIMALS>2</NUMDECIMALS>
	</record>
</record-list>
'
        );


        foreach ($new_items->ToSimplePHP() as $new_item) {
            /** @noinspection PhpUndefinedVariableInspection */
            $item['UNIT'];
            $ok = $this->_UOMMgr->set($new_item);
            if (!$ok) {
                epp("$source: Set failed");
                eppp($item);
            }
        }

        /**
         * @var bool|DOM|DataRetriever $dr
         */
        $dr = GetDataRetriever(
            DOM::CreateFromString(
                '
<data-retriever id="1" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<connection type="entity" entity="UOM"/>
    <column-list> 
		<column name="UNIT" seq="1" />
		<column name="NUMDECIMALS" seq="2" />
	</column-list>
	<filter-list>
		<filter attr="UNIT" op="like" value="'.$this->_idPrefix.'%" seq="1"/>
	</filter-list>
</data-retriever>
		'
            )
        );

        $dr->Bind();

        $result = $dr->FetchAllXML();
        //epp("RESULT");
        //eppp($result->ToSimplePHP());
        //epp("new Items");
        //eppp($expected_items->ToSimplePHP());
        $this->assert(is_object($result) && $result->Equals($expected_items), 'Returned record did not match original.');
        ExecSimpleStmt("DELETE FROM icuom WHERE unit like '".$this->_idPrefix."%'  AND cny# =".$this->_cny);
        /** @noinspection PhpUndefinedVariableInspection */
        if (!$ok) {
            epp('Failed deleting record');
        }
        epp("END testSet_p");
    }

    /**
     *
     */
    public function testDelete_p()
    {
        epp("BEGIN testDelete_p");

        $items = DOM::CreateFromString(
            '
<record-list>
	<record>
		<UNIT>'.$this->_idPrefix.'</UNIT>
		<NUMDECIMALS>1</NUMDECIMALS>
	</record>
</record-list>
'
        );
        $expected_items = DOM::CreateFromString(
            '
<record-list>
</record-list>
'
        );

        foreach ($items->ToSimplePHP() as $item) {
            $ok = $this->_UOMMgr->add($item);
            if (!$ok) {
                epp("UOMManagerTester::testGet : Add failed");
                eppp($item);
            }
            $ok = $this->_UOMMgr->Delete($this->_idPrefix);
            if (!$ok) {
                epp("UOMManagerTester::testGet : Delete failed");
                eppp($item);
            }
        }

        /**
         * @var bool|DOM|DataRetriever $dr
         */
        $dr = GetDataRetriever(
            DOM::CreateFromString(
                '
<data-retriever id="1" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<connection type="entity" entity="UOM"/>
    <column-list> 
		<column name="UNIT" seq="1" />
		<column name="NUMDECIMALS" seq="2" />
	</column-list>
	<filter-list>
		<filter attr="UNIT" op="=" value="'.$this->_idPrefix.'" seq="1"/>
	</filter-list>
</data-retriever>
		'
            )
        );

        $dr->Bind();

        $result = $dr->FetchAllXML();
        //epp("RESULT");
        //eppp($result->ToSimplePHP());
        //epp("new Items");
        //eppp($expected_items->ToSimplePHP());
        $this->assert(is_object($result) && $result->Equals($expected_items), 'Returned record did not match original.');

        epp("END testDelete_p");
    }

    /**
     *
     */
    public function testValidate1_n()
    {
        epp("BEGIN testValidate1_n");

        $overflow = str_repeat('1', $this->_infoMap['NUMDECIMALS']['maxlength']+1);

        $items = DOM::CreateFromString(
            '
<record-list>
	<record>
		<UNIT>'.$this->_idPrefix.'</UNIT>
		<NUMDECIMALS>A</NUMDECIMALS>
	</record>
	<record>
		<UNIT>'.$this->_idPrefix.'</UNIT>
		<NUMDECIMALS>.</NUMDECIMALS>
	</record>
	<record>
		<UNIT>'.$this->_idPrefix.'</UNIT>
		<NUMDECIMALS>'.$overflow.'</NUMDECIMALS>
	</record>
	<record>
		<UNIT>'.$this->_idPrefix.'</UNIT>
		<NUMDECIMALS>-1</NUMDECIMALS>
	</record>
</record-list>
'
        );

        $success = true;

        $caseNo = 1;
        foreach ($items->ToSimplePHP() as $item) {
            $success = $this->_UOMMgr->add($item);
            if ($success) {
                epp("UOMManagerTester::testGet : Add succeeded where failure was expected. CASE[$caseNo]");
                eppp($item);
            }
            $caseNo++;
        }

        $this->assert(!$success, 'Validation Test Failed.');
        
        if ($success) {
            $ok = $this->_UOMMgr->Delete($this->_idPrefix);
            if (!$ok) { 
                epp('Failed deleting record');
            }
        }
        epp("END testValidate1_n");
    }

    /**
     *
     */
    public function testValidate2_n()
    {
        epp("BEGIN testValidate2_n");

        $defaultLength = isl_strlen($this->_idPrefix);
        $padNeeded = intval($this->_infoMap['UNIT']['type']['maxlength']) - $defaultLength;
        $overflowID = $this->_idPrefix . str_repeat('J', $padNeeded+1);

        $IDs = array (
        $overflowID,
        ':::',
        );

        $items = DOM::CreateFromString(
            '
<record-list>
	<record>
		<UNIT>'.$IDs[0].'</UNIT>
		<NUMDECIMALS>0</NUMDECIMALS>
	</record>
	<record>
		<UNIT>'.$IDs[1].'</UNIT>
		<NUMDECIMALS>0</NUMDECIMALS>
	</record>
</record-list>
'
        );

        $success = true;

        $caseNo = 0;
        $failures = array();
        foreach ($items->ToSimplePHP() as $item) {
            $success = $this->_UOMMgr->add($item);
            $failures[$caseNo] = 0;
            if ($success) {
                epp("UOMManagerTester::testGet : Add succeeded where failure was expected. CASE[$caseNo]");
                eppp($item);
                $failures[$caseNo] = 1;
            }
            $caseNo++;
        }

        $this->assert(!$success, 'Validation Test Failed.');
        
        if ($success) {
            foreach ($failures as $caseNo => $val) {
                if ($val == 1) {
                    ExecSimpleStmt("DELETE FROM icuom WHERE unit = '".$IDs[$caseNo]."'  AND cny# =".$this->_cny);
                    /** @noinspection PhpUndefinedVariableInspection */
                    if (!$ok) {
                        epp('Failed deleting record');
                       }
                }
            }
        }
        epp("END testValidate2_n");
    }
}

