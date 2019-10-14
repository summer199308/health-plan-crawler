cheerio = require 'cheerio'

str = """
<div class="ps-detail__service" id="simplifiedDeductibleDetail">
							<div class="u-table-cell ps-detail__service-label">



										Yearly Deductible


							</div>

<div class="details u-table-cell">
	<div class="u-show-block-xs u-margin-top-10">
		<a data-placement="right" rel="tooltip" href="#" data-original-title="The plan's primary provider network. Seeing health care providers that are in network will result in lower out-of-pocket costs.">
			In Network
		</a>
	</div>




		<p>$6300 (Individual)</p>





				<p>$12600 (Family)</p>






</div>

<div class="details u-table-cell">
	<div class="u-show-block-xs u-margin-top-10">
		<a data-placement="right" rel="tooltip" href="#" data-original-title="Doctors who aren't within a plan's network(s) are considered out of network. Seeing doctors outside of a plan's network can be very costly.">
			Out-of-Network
		</a>
	</div>












				Not Applicable




</div>

<div class="details u-table-cell"></div>
</div>
"""


$ = cheerio.load str
fieldName = $('div.ps-detail__service-label').text().trim()
console.log $('div.details p').first().text()
individualAnnualDeductibleAmount = $('div.details p').first()?.text()?.trim().split(" ", 1).toString()
familyAnnualDeductibleAmount = $('div.details p').last()?.text()?.trim().split(" ", 1).toString()
console.log 'DDDDD'
console.log fieldName
console.log individualAnnualDeductibleAmount
console.log familyAnnualDeductibleAmount
