//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2017-2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#ifndef _EXPAT_PREFIX_SYMBOLS_H_
#define _EXPAT_PREFIX_SYMBOLS_H_

#define EXPAT_PREFIX AWS

#define EXPAT_ADD_PREFIX(a, b) EXPAT_ADD_PREFIX_INNER(a, b)
#define EXPAT_ADD_PREFIX_INNER(a, b) a ## _ ## b

#define XmlGetUtf16InternalEncoding EXPAT_ADD_PREFIX(EXPAT_PREFIX, XmlGetUtf16InternalEncoding)
#define XmlGetUtf8InternalEncoding EXPAT_ADD_PREFIX(EXPAT_PREFIX, XmlGetUtf8InternalEncoding)
#define XmlInitEncoding EXPAT_ADD_PREFIX(EXPAT_PREFIX, XmlInitEncoding)
#define XmlInitUnknownEncoding EXPAT_ADD_PREFIX(EXPAT_PREFIX, XmlInitUnknownEncoding)
#define XmlParseXmlDecl EXPAT_ADD_PREFIX(EXPAT_PREFIX, XmlParseXmlDecl)
#define XmlSizeOfUnknownEncoding EXPAT_ADD_PREFIX(EXPAT_PREFIX, XmlSizeOfUnknownEncoding)
#define XmlUtf16Encode EXPAT_ADD_PREFIX(EXPAT_PREFIX, XmlUtf16Encode)
#define XmlUtf8Encode EXPAT_ADD_PREFIX(EXPAT_PREFIX, XmlUtf8Encode)
#define _INTERNAL_trim_to_complete_utf8_characters EXPAT_ADD_PREFIX(EXPAT_PREFIX, _INTERNAL_trim_to_complete_utf8_characters)
#define XML_DefaultCurrent EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_DefaultCurrent)
#define XML_ErrorString EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_ErrorString)
#define XML_ExpatVersion EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_ExpatVersion)
#define XML_ExpatVersionInfo EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_ExpatVersionInfo)
#define XML_ExternalEntityParserCreate EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_ExternalEntityParserCreate)
#define XML_FreeContentModel EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_FreeContentModel)
#define XML_GetBase EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_GetBase)
#define XML_GetBuffer EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_GetBuffer)
#define XML_GetCurrentByteCount EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_GetCurrentByteCount)
#define XML_GetCurrentByteIndex EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_GetCurrentByteIndex)
#define XML_GetCurrentColumnNumber EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_GetCurrentColumnNumber)
#define XML_GetCurrentLineNumber EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_GetCurrentLineNumber)
#define XML_GetErrorCode EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_GetErrorCode)
#define XML_GetFeatureList EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_GetFeatureList)
#define XML_GetIdAttributeIndex EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_GetIdAttributeIndex)
#define XML_GetInputContext EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_GetInputContext)
#define XML_GetParsingStatus EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_GetParsingStatus)
#define XML_GetSpecifiedAttributeCount EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_GetSpecifiedAttributeCount)
#define XML_MemFree EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_MemFree)
#define XML_MemMalloc EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_MemMalloc)
#define XML_MemRealloc EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_MemRealloc)
#define XML_Parse EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_Parse)
#define XML_ParseBuffer EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_ParseBuffer)
#define XML_ParserCreate EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_ParserCreate)
#define XML_ParserCreateNS EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_ParserCreateNS)
#define XML_ParserCreate_MM EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_ParserCreate_MM)
#define XML_ParserFree EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_ParserFree)
#define XML_ParserReset EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_ParserReset)
#define XML_ResumeParser EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_ResumeParser)
#define XML_SetAttlistDeclHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetAttlistDeclHandler)
#define XML_SetBase EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetBase)
#define XML_SetCdataSectionHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetCdataSectionHandler)
#define XML_SetCharacterDataHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetCharacterDataHandler)
#define XML_SetCommentHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetCommentHandler)
#define XML_SetDefaultHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetDefaultHandler)
#define XML_SetDefaultHandlerExpand EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetDefaultHandlerExpand)
#define XML_SetDoctypeDeclHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetDoctypeDeclHandler)
#define XML_SetElementDeclHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetElementDeclHandler)
#define XML_SetElementHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetElementHandler)
#define XML_SetEncoding EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetEncoding)
#define XML_SetEndCdataSectionHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetEndCdataSectionHandler)
#define XML_SetEndDoctypeDeclHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetEndDoctypeDeclHandler)
#define XML_SetEndElementHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetEndElementHandler)
#define XML_SetEndNamespaceDeclHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetEndNamespaceDeclHandler)
#define XML_SetEntityDeclHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetEntityDeclHandler)
#define XML_SetExternalEntityRefHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetExternalEntityRefHandler)
#define XML_SetExternalEntityRefHandlerArg EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetExternalEntityRefHandlerArg)
#define XML_SetHashSalt EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetHashSalt)
#define XML_SetNamespaceDeclHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetNamespaceDeclHandler)
#define XML_SetNotStandaloneHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetNotStandaloneHandler)
#define XML_SetNotationDeclHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetNotationDeclHandler)
#define XML_SetParamEntityParsing EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetParamEntityParsing)
#define XML_SetProcessingInstructionHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetProcessingInstructionHandler)
#define XML_SetReturnNSTriplet EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetReturnNSTriplet)
#define XML_SetSkippedEntityHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetSkippedEntityHandler)
#define XML_SetStartCdataSectionHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetStartCdataSectionHandler)
#define XML_SetStartDoctypeDeclHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetStartDoctypeDeclHandler)
#define XML_SetStartElementHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetStartElementHandler)
#define XML_SetStartNamespaceDeclHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetStartNamespaceDeclHandler)
#define XML_SetUnknownEncodingHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetUnknownEncodingHandler)
#define XML_SetUnparsedEntityDeclHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetUnparsedEntityDeclHandler)
#define XML_SetUserData EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetUserData)
#define XML_SetXmlDeclHandler EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_SetXmlDeclHandler)
#define XML_StopParser EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_StopParser)
#define XML_UseForeignDTD EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_UseForeignDTD)
#define XML_UseParserAsHandlerArg EXPAT_ADD_PREFIX(EXPAT_PREFIX, XML_UseParserAsHandlerArg)
#define XmlPrologStateInit EXPAT_ADD_PREFIX(EXPAT_PREFIX, XmlPrologStateInit)

#endif // _EXPAT_PREFIX_SYMBOLS_H_
