<?xml version="1.0" encoding="UTF-8"?>
<!-- $Id: htm-teip.xsl 708 2008-04-15 10:52:58Z zau $ -->
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">

  <xsl:template match="p">
    <p>
      <xsl:apply-templates/>
    </p>
  </xsl:template>
  
</xsl:stylesheet>