pragma solidity ^0.8.21;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC7578, Properties, Amount } from "./interfaces/IERC7578.sol";

/**
 * @title ERC7578
 * @author DESAT
 * @notice Implementation of the ERC-7578: Physical Asset Redemption standard
 **/
contract ERC7578 is ERC721, IERC7578 {
    /**
     * @notice Thrown when the properties of a token are not initialized
     */
    error PropertiesUninitialized();

    /**
     * @notice Retrieves the properties of the `tokenId` token
     */
    mapping(uint256 tokenId => Properties) private _properties;

    /**
     * @notice Initializes the name and symbol of the ERC-721 collection
     */
    constructor(string memory _name, string memory _symbol) ERC721(_name, _symbol) {}

    /**
     * @inheritdoc IERC7578
     */
    function getPropertiesOf(uint256 tokenId) public view override returns (Properties memory properties) {
        properties = _properties[tokenId];
    }

    /**
     * @notice Initializes the ERC-7578 properties of the `tokenId` token
     *
     * WARNING: This method should only be called within a function that has appropriate access control
     * It is recommended to restrict access to trusted Externally Owned Accounts (EOAs),
     * authorized contracts, or implement a Role-Based Access Control (RBAC) mechanism
     * Failure to properly secure this method could lead to unauthorized modification of token properties
     *
     * Emits a {PropertiesSet} event
     */
    function _setPropertiesOf(uint256 tokenId, Properties calldata properties) internal {
        _properties[tokenId] = Properties({
            tokenIssuer: properties.tokenIssuer,
            assetHolder: properties.assetHolder,
            storageLocation: properties.storageLocation,
            terms: properties.terms,
            jurisdiction: properties.jurisdiction,
            declaredValue: Amount({
                currency: properties.declaredValue.currency,
                value: properties.declaredValue.value
            })
        });

        emit PropertiesSet(tokenId, _properties[tokenId]);
    }

    /**
     * @notice Removes the properties of the `tokenId` token
     * @param tokenId The unique identifier of the token whose properties are to be removed
     *
     * Emits a {PropertiesRemoved} event
     */
    function _removePropertiesOf(uint256 tokenId) internal {
        delete _properties[tokenId];
        emit PropertiesRemoved(tokenId);
    }

    /**
     * @notice Override of the {_update} function to remove the properties of the `tokenId` token or
     * to check if they are set before minting
     * @param tokenId The unique identifier of the token being minted or burned
     */
    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        address from = _ownerOf(tokenId);
        if (to == address(0)) {
            _removePropertiesOf(tokenId);
        } else if (from == address(0)) {
            if (bytes(_properties[tokenId].tokenIssuer).length == 0) revert PropertiesUninitialized();
        }

        return super._update(to, tokenId, auth);
    }
}