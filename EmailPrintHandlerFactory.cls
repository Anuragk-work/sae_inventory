<?php
/**
 *    This is the factory class for print handlers
 *
 *    @author    Valer Crisan <vcrisan@intacct.com>
 *    @copyright 2011 Intacct Corporation, All Rights Reserved
 */


/**
 * Print Handler Factory class.
 * 
 * @author vcrisan
 */
class EmailPrintHandlerFactory
{

    /**
     * Retrieve the appropriate print handler
     *
     * @param array $params the parameters supplied by the caller
     *
     * @return EmailPrintHandler|null
     */

    static function getHandler($params)
    {
        switch ($params['mod']) {
            case 'ar':
                return new ARPrintHandler($params);
            case 'so':
                return new SODocumentPrintHandler($params);
            case 'po':
                return new PODocumentPrintHandler($params);
            case 'inv':
                return new OEPrintHandler($params);
            case 'cr': // cr is not module, it refers to Change Request
                return new CRPrintHandler($params);
            case 'pco': // pco is not module, it refers to Project Change Order
                return new PCOPrintHandler($params);
            case 'vendorcompliance':
                return new CompliancePrintHandler($params);
        }
        return null;
    }


    /**
     * Used to send out single document
     *
     * @param array $params
     *
     * @return EmailPrintHandler
     */
    public static function getSingleDocumentEmailHandler( $params )
    {
        return self::getHandler(self::getSingleEmailHandlerParams($params));
    }

    /**
     * @param array $params
     *
     * @return array
     */
    private static function getSingleEmailHandlerParams(array $params): array
    {
        $sendersname = $params['sendersname'];
        if (preg_match("/^[A-Z0-9(\s'.,&\-)]+$/i", $params['sendersname']) !== 1) {
            $sendersname = htmlspecialchars( $params['sendersname'], ENT_QUOTES);
        }

        return [
            'docidforemail' => [
                $params['txn_vid'] => 'E',
            ],
            'mod' => $params['mod'],
            'entity' => $params['entity'],
            'sendersname' => $sendersname,
            'sendersemail' => $params['sendersemail'],
            'overridenFrom' => $params['overridenFrom'],
            'userprefdateformat' => $params['userprefdateformat'],
            'emailSubject' => [
                $params['txn_vid'] => $params['emailSubject'],
            ],
            'emailMsg' => [
                $params['txn_vid'] => $params['emailMsg'],
            ],
            'custemail' => [
                $params['txn_vid'] => $params['emailTo'],
            ],
            'custccemail' => [
                $params['txn_vid'] => htmlspecialchars($params['emailCC'], ENT_QUOTES),
            ],
            'custbccemail' => [
                $params['txn_vid'] => htmlspecialchars($params['emailBCC'], ENT_QUOTES),
            ],
            'emailtemplate' => [
                $params['txn_vid'] => $params['emailTemplateKey'],
            ],
            'deliveryLogKeys' => [
                $params['txn_vid'] => $params['deliveryLogKey'],
            ]
        ];
    }

    /**
     * @param array $params
     *
     * @return array
     */
    private static function getSinglePrintHandlerParams(array $params): array
    {
        return [
            'docidforprint' => [
                $params['txn_pid'] => 'P',
            ],
            'mod' => $params['mod'],
            'entity' => $params['entity'],
            'overridenFrom' => $params['overridenFrom'],
            'userprefdateformat' => $params['userprefdateformat']
        ];
    }

    /**
     * Used to send out single document
     *
     * @param array $params
     *
     * @return EmailPrintHandler
     */
    public static function getSingleDocumentPrintEmailHandler( $params )
    {
        $printParams = [];
        $emailParams = [];
        if (!empty($params['txn_pid'])) {
            $printParams = self::getSinglePrintHandlerParams($params);
        }

        if (!empty($params['txn_vid'])) {
            $emailParams = self::getSingleEmailHandlerParams($params);
        }

        $new_params = INTACCTarray_merge($printParams, $emailParams);

        return self::getHandler($new_params);
    }

    /**
     * Private constructor so nobody can instantiate this class
     */
    private function __construct()
    {
    }
}