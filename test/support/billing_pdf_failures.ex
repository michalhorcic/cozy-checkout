defmodule CozyCheckout.BillingPdfFailures.MissingChrome do
  use ChromicPDF.Supervisor
end

defmodule CozyCheckout.BillingPdfFailures.Shutdown do
  def print_to_pdf(_, _), do: exit(:shutdown)
end

defmodule CozyCheckout.BillingPdfFailures.Killed do
  def print_to_pdf(_, _), do: Process.exit(self(), :kill)
end

defmodule CozyCheckout.BillingPdfFailures.Slow do
  def print_to_pdf(_, _), do: Process.sleep(:infinity)
end
