package services

const verificationEmailHTML = `<!DOCTYPE html>
<html>
<head>
<style>
body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol"; line-height: 1.6; color: #1f2937; background-color: #f5f3ff; margin: 0; padding: 20px; }
.container { padding: 20px; max-width: 600px; margin: 20px auto; background-color: #ffffff; border: 1px solid #e9d5ff; border-radius: 8px; }
.header { font-size: 24px; font-weight: bold; color: #743ee4; margin-bottom: 15px; }
.content { padding: 30px; text-align: center; }
.code { font-size: 36px; font-weight: bold; letter-spacing: 8px; color: #743ee4; background-color: #f1f3f5; padding: 15px 20px; border-radius: 5px; display: inline-block; margin: 20px 0; }
.footer { margin-top: 20px; font-size: 12px; color: #6b7280; text-align: center; }
p { margin-bottom: 1em; }
</style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>%s</h1>
    </div>
    <div class="content">
      <p>%s</p>
      <div class="code">%s</div>
    </div>
    <div class="footer">
      © %d Poof. All rights reserved.
    </div>
  </div>
</body>
</html>`

const internalNotificationEmailHTML = `<!DOCTYPE html>
<html>
<head>
<style>
body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol"; line-height: 1.6; color: #1f2937; background-color: #f5f3ff; margin: 0; padding: 20px; }
.container { padding: 20px; max-width: 600px; margin: 20px auto; background-color: #ffffff; border: 1px solid #e9d5ff; border-radius: 8px; }
.header { font-size: 24px; font-weight: bold; color: #743ee4; margin-bottom: 15px; }
.content { padding: 20px; }
.footer { margin-top: 20px; font-size: 12px; color: #6b7280; text-align: center; }
p { margin-bottom: 1em; }
ul { list-style: none; padding: 0; }
li { margin-bottom: 10px; }
strong { color: #000; }
</style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h2>%s</h2>
    </div>
    <div class="content">
      %s
    </div>
    <div class="footer">
      © %d Poof. All rights reserved.
    </div>
  </div>
</body>
</html>`
