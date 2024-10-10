<?php

class InvSelfHelpEditor extends FormEditor
{


    /**
     * @param array $_params
     */
    public function __construct($_params = [])
    {
        // TOFO: How are these different than getFormTokens()??  Are these used in this cls file?
        $localTokens =[
            "IA.TODO",
        ];
        $this->additionalTokens = array_merge($this->additionalTokens, $localTokens);
        parent::__construct($_params);
    }

    /**
     * Get the JS tokens
     *
     * @return string[]
     */
    protected function getFormTokens() : array
    {
        array_push( $this->textTokens
            ,"IA.DOWNLOAD"      // OR WHATEVER
            ,'IA.START_DATE_CANNOT_BE_GREATER_THAN_END_DATE'
            ,"IA.LOADING");
        return parent::getFormTokens();
    }

    /**
     * can print
     *
     * @return bool
     */
    protected function canPrint()
    {
        return false;
    }

    /**
     * can save
     *
     * @return bool
     */
    protected function canSave()
    {
        return false;
    }

    /**
     * canSaveAndNew
     *
     * @return bool
     */
    protected function canSaveAndNew()
    {
        return false;
    }


    /**
     * @param string $state
     *
     * @return array
     */
    public function getStandardButtons($state)
    {
        $buttons = parent::getStandardButtons($state);  // REALLY????

        /* DO WE NEED SOMETHING LIKE THIS????
        if ( $this->kShowNewState === $state ) {
            $buttons1 = array();
            $this->setButtonDetails($buttons1, 'runnow',  'runnow', GT($this->textTokens,"IA.RUN_NOW"),  'RUNNOW', true, 'runHealthCheck(this)',false);
            $buttons = array_merge($buttons1, $buttons);
        }
        ************ */
        return $buttons;
    }


    /**
     * Get the list of JS files to include in the editor screen
     *
     * @return array    the list of JS files to include
     */
    protected function getJavaScriptFileNames()
    {
        return array('../resources/js/invselfhelp.js');
    }


    /**
     * Argh!  We have a manager, but not an ENTITY manager.  Let's hope this works....
     *
     * @return InvSelfHelpManager
     */
    public function getEntityMgr()
    {
        $em = parent::getEntityMgr();
        assert($em instanceof InvSelfHelpManager);  // lets just be sure
        return $em;
    }

    /**
     * @param array         $_params
     * @param bool          $offline
     * @param string|false  $out
     *
     * @return bool
     */
    public function Editor_Deliver(&$_params, $offline, &$out)
    {
        $obj = $this->getViewData();

        $ok = $this->getEntityMgr()->generateReport($obj['DOWNLOAD'] ?? 'CODEBUG', $obj);
        if (! $ok) {
            include 'popuperror.phtml'; // show the error.
        }
        return $ok;
    }

}
