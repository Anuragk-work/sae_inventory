<?php
/**
 * No special behavior for Inventory Control. But the framework needs a class
 * named InvDocRecallsManager to behave correctly.
 *
 * @author    Samvel Mirijanyan <smirijanyan@intacct.com>
 * @copyright 2000-2015 Intacct Corporation All, Rights Reserved
 */

class InvDocRecallsManager extends DocRecallsManager
{


    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $this->populateDocIdforAPI($values);
        return parent::regularAdd($values);
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularSet(&$values)
    {
        $this->populateDocIdforAPI($values);
        return parent::regularSet($values);
    }

    /**
     * @param array $values
     *
     * @return void
     */
    private function populateDocIdforAPI(&$values)
    {
        if ($values['RECDOCPAR'] === $values['RECDOCPARRECORDNO']){
            $gManagerFactory = Globals::$g->gManagerFactory;
            $invdocParmsManager = $gManagerFactory->getManager('invdocumentparams');
            $recDocPar = $invdocParmsManager->BaseGet($values['RECDOCPARRECORDNO']);
            $values['RECDOCPAR'] = $recDocPar['DOCID'];
        }
    }

}